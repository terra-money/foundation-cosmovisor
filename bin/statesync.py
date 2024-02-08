#!/usr/bin/env python3

import logging, requests, time, tomlkit
import cvcontrol, cvutils


SNAPSHOT_INTERVAL = 2000
RPC_PORT = 26657
P2P_PORT = 26656


def statesync_setup(ctx):
    logging.info("Setting up statesync...")

    rpc_address = f"{ctx['chain_id']}-sync.{ctx['domain']}"
    logging.info(f"  rpc_address: {rpc_address}")

    # collect params
    try:
        rpc_status = requests.get(f"http://{rpc_address}:{RPC_PORT}/status").json()
        rpc_id = rpc_status["result"]["node_info"]["id"]
        logging.info(f"  rpc_id: {rpc_id}")

        latest_block = requests.get(f"http://{rpc_address}:{RPC_PORT}/block").json()
        latest_height = latest_block["result"]["block"]["header"]["height"]
        trust_height = int(latest_height) - SNAPSHOT_INTERVAL
        logging.info(f"  latest_height: {latest_height}")
        logging.info(f"  trust_height: {trust_height}")

        trust_block = requests.get(f"http://{rpc_address}:{RPC_PORT}/block?height={trust_height}").json()
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
    config_toml_data["statesync"]["rpc_servers"] = f"http://{rpc_address}:{RPC_PORT},http://{rpc_address}:{RPC_PORT}"
    config_toml_data["statesync"]["trust_height"] = trust_height
    config_toml_data["statesync"]["trust_hash"] = trust_hash
    config_toml_data["statesync"]["temp_dir"] = "/app/tmp"
    config_toml_data["statesync"]["chunk_fetchers"] = 1

    # setup persistent/unconditional peer
    if not rpc_id in config_toml_data["p2p"]["persistent_peers"]:
        config_toml_data["p2p"]["persistent_peers"] += f",{rpc_id}@{rpc_address}:{P2P_PORT}"
    if not rpc_id in config_toml_data["p2p"]["unconditional_peer_ids"]:
        config_toml_data["p2p"]["unconditional_peer_ids"] = rpc_id

    with open(config_toml_path, "w") as file:
        tomlkit.dump(config_toml_data, file)

    return True


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


def statesync(ctx):
    if ctx["profile"] != "snap":
        logging.error("Not a snap node. Statesync disabled.")
    else:
        if statesync_setup(ctx):
            cvutils.unsafe_reset_all(ctx)
            cvcontrol.start_process("cosmovisor")
            wait_for_localhost(ctx)
            cvcontrol.stop_process("cosmovisor")
        else:
            logging.error("Cannot setup statesync.")
