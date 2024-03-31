#!/usr/bin/env python3

import logging, os, requests, shutil, time, tomlkit
import cvcontrol
import cvutils
import argparse

def statesync_setup(ctx):
    logging.info("Setting up statesync...")

    rpc_address = f"{ctx['chain_name']}-sync.{ctx['domain']}"
    rpc_port = ctx.get("rpc_port")
    p2p_port = ctx.get("p2p_port")
    snapshot_interval = ctx.get("snapshot_interval")
    logging.info(f"  rpc_address: {rpc_address}")

    # collect params
    try:
        rpc_status = requests.get(f"http://{rpc_address}:{rpc_port}/status").json()
        rpc_id = rpc_status["result"]["node_info"]["id"]
        logging.info(f"  rpc_id: {rpc_id}")

        latest_block = requests.get(f"http://{rpc_address}:{rpc_port}/block").json()
        latest_height = latest_block["result"]["block"]["header"]["height"]
        trust_height = int(latest_height) - snapshot_interval
        logging.info(f"  latest_height: {latest_height}")
        logging.info(f"  trust_height: {trust_height}")

        trust_block = requests.get(f"http://{rpc_address}:{rpc_port}/block?height={trust_height}").json()
        trust_hash = trust_block["result"]["block_id"]["hash"]
        logging.info(f"  trust_hash: {trust_hash}")
    except:
        return False

    # apply params
    config_toml_path = ctx["config_toml"]
    with open(config_toml_path, "r") as file:
        config_toml_data = tomlkit.load(file)

    # apply statesync config
    config_toml_data["statesync"]["enable"] = True
    config_toml_data["statesync"]["rpc_servers"] = f"http://{rpc_address}:{rpc_port},http://{rpc_address}:{rpc_port}"
    config_toml_data["statesync"]["trust_height"] = trust_height
    config_toml_data["statesync"]["trust_hash"] = trust_hash
    config_toml_data["statesync"]["temp_dir"] = "/app/tmp"
    config_toml_data["statesync"]["chunk_fetchers"] = 1

    # setup persistent/unconditional peer
    if not rpc_id in config_toml_data["p2p"]["persistent_peers"]:
        config_toml_data["p2p"]["persistent_peers"] += f",{rpc_id}@{rpc_address}:{p2p_port}"
    if not rpc_id in config_toml_data["p2p"]["unconditional_peer_ids"]:
        config_toml_data["p2p"]["unconditional_peer_ids"] = rpc_id

    with open(config_toml_path, "w") as file:
        tomlkit.dump(config_toml_data, file)

    return True


def datadir_cleanup(ctx):
    logging.info("Cleaning up data directory...")
    data_dir = ctx.get("data_dir")
    keep_data_files = ["wasm", "priv_validator_state.json"]

    for item in os.listdir(data_dir):
        item_path = os.path.join(data_dir, item)
        if item in keep_data_files:
            continue
        elif os.path.isfile(item_path):
            os.remove(item_path)
            logging.info(f"  deleted file: {item_path}")
        elif os.path.isdir(item_path):
            shutil.rmtree(item_path)
            logging.info(f"  deleted directory: {item_path}")


def wait_for_localhost(ctx):
    logging.info("Waiting for localhost to catch up...")
    status_url = ctx["status_url"]

    while True:
        time.sleep(30)
        try:
            status = requests.get(status_url).json()
            catching_up = status["result"]["sync_info"]["catching_up"]

            if not catching_up:
                break
        except:
            continue


def main(ctx):
    if ctx["profile"] == "archive":
        logging.error("Archive node. Statesync disabled.")
        return 1
    else:
        if statesync_setup(ctx):
            datadir_cleanup(ctx)
            cvcontrol.start_process("cosmovisor")
            wait_for_localhost(ctx)
            cvcontrol.stop_process("cosmovisor")
        else:
            logging.error("Cannot setup statesync.")
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(description='Load data from image snapshot.')
    parser.add_argument('--p2p-port', dest="p2p_port", type=str, help='P2P port')
    parser.add_argument('--rpc-prot', dest="rpc_port", type=str, help='RPC port')
    parser.add_argument('--interval', dest="snapshot_interval", type=str, help='Snapshot interval value')

    args = parser.parse_args()
    ctx = cvutils.get_ctx(args)

    exit_code = main(args)

    exit(exit_code)