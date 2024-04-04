#!/usr/bin/env python3

import os
import requests
import shutil
import time
import tomlkit
import logging 
import cvcontrol
import cvutils
import argparse
import urllib.parse
from rpcstatus import RpcStatus

def get_statesync_params(ctx):
    """
    Collects parameters required for statesync.

    :param ctx: Context containing 'statesync_rpc' and 'snapshot_interval'.
    :return: Tuple containing rpc_id, trust_height, and trust_hash.
    """
    rpc_address = ctx.get("statesync_rpc")
    snapshot_interval = ctx.get("snapshot_interval")
    logging.info(f"RPC address: {rpc_address}")

    rpcstatus = RpcStatus(f"{rpc_address}/status")
    rpc_id = rpcstatus.node_info.id
    logging.info(f"RPC ID: {rpc_id}")

    latest_height = rpcstatus.sync_info.latest_block_height
    trust_height = int(latest_height) - snapshot_interval
    logging.info(f"Latest height: {latest_height}")
    logging.info(f"Trust height: {trust_height}")

    trust_block_raw = requests.get(f"{rpc_address}/block?height={trust_height}").json()
    trust_block = trust_block_raw.get('result', trust_block_raw)
    trust_hash = trust_block["block_id"]["hash"]
    logging.info(f"Trust hash: {trust_hash}")

    return rpc_id, trust_height, trust_hash

def apply_statesync_config(ctx, rpc_id, trust_height, trust_hash):
    """
    Applies the statesync configuration.

    :param ctx: Context containing 'config_toml' and other necessary keys.
    :param rpc_id: The RPC ID to use.
    :param trust_height: The trust height.
    :param trust_hash: The trust hash.
    """
    rpc_address = ctx.get("statesync_rpc")
    rpc_split = urllib.parse.urlsplit(rpc_address)
    p2p_port = ctx.get("p2p_port") # presuming the same as self
    config_toml_path = ctx["config_toml"]

    with open(config_toml_path, "r") as file:
        config_toml_data = tomlkit.load(file)

    config_toml_data["statesync"]["enable"] = True
    config_toml_data["statesync"]["rpc_servers"] = f"{rpc_address},{rpc_address}"
    config_toml_data["statesync"]["trust_height"] = trust_height
    config_toml_data["statesync"]["trust_hash"] = trust_hash
    config_toml_data["statesync"]["chunk_fetchers"] = 1

    if not rpc_id in config_toml_data["p2p"]["persistent_peers"]:
        config_toml_data["p2p"]["persistent_peers"] += f",{rpc_id}@{rpc_split.hostname}:{p2p_port}"
    if not rpc_id in config_toml_data["p2p"]["unconditional_peer_ids"]:
        config_toml_data["p2p"]["unconditional_peer_ids"] = rpc_id

    with open(config_toml_path, "w") as file:
        tomlkit.dump(config_toml_data, file)
        

def datadir_cleanup(ctx):
    """
    Cleans up the data directory, deleting all files and directories except specified ones.

    :param ctx: Context dictionary containing 'data_dir'.
    """
    logging.info("Cleaning up data directory...")
    data_dir = ctx.get("data_dir")

    if not os.path.exists(data_dir):
        logging.warning(f"Data directory {data_dir} does not exist.")
        return

    keep_data_files = ["wasm", "priv_validator_state.json"]

    for item in os.listdir(data_dir):
        item_path = os.path.join(data_dir, item)
        if item in keep_data_files:
            continue

        try:
            if os.path.isfile(item_path):
                os.remove(item_path)
                logging.info(f"Deleted file: {item_path}")
            elif os.path.isdir(item_path):
                shutil.rmtree(item_path)
                logging.info(f"Deleted directory: {item_path}")
        except Exception as e:
            logging.error(f"Error deleting {item_path}: {e}")


def wait_for_localhost(ctx, sleep_time=30, max_retries=None):
    """
    Waits for the localhost server to catch up.

    :param ctx: Context dictionary containing 'status_url'.
    :param sleep_time: Time to wait between each check, in seconds. Default is 30.
    :param max_retries: Maximum number of retries. Infinite if None. Default is None.
    """
    logging.info("Waiting for localhost to catch up...")
    status_url = ctx["status_url"]
    retries = 0

    while True:
        time.sleep(sleep_time)
        try:
            rpcstatus = RpcStatus(status_url)
            if not rpcstatus.is_catching_up():
                break
        except Exception as e:
            logging.error(f"Error checking status: {e}")
            if max_retries is not None and retries >= max_retries:
                logging.error("Max retries reached. Exiting.")
                break
        retries += 1


def main(ctx):
    """
    Main function to set up statesync.

    :param ctx: Context containing necessary configuration.
    :return: Boolean indicating success or failure.
    """
    if ctx["profile"] == "archive":
        logging.error("Archive node. Statesync disabled.")
        return 1

    try:
        params = get_statesync_params(ctx)
        rpc_id, trust_height, trust_hash = params
    except Exception as e:
        logging.error(f"Error retrieveing statesync params. {e}")
        return 1
    
    
    logging.info("Configuring statesync")
    try:
        apply_statesync_config(ctx, rpc_id, trust_height, trust_hash)
    except Exception as e:
        logging.error(f"Error configuring statesync. {e}")
        return 1
    
    logging.info("Preparing data directory")
    try:
        datadir_cleanup(ctx)
    except Exception as e:
        logging.error(f"Error preparing data directory. {e}")
        return 1
    
    logging.info("Starting State Sync...")
    try:
        cvcontrol.start_process("cosmovisor")
        wait_for_localhost(ctx)
        cvcontrol.stop_process("cosmovisor")
    except Exception as e:
        logging.error(f"State Sync Failed {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(description='Load data from image snapshot.')
    parser.add_argument('--rpc', dest="statesync_rpc", type=str, help='Rpc to use for statesync')
    parser.add_argument('--p2p-port', dest="p2p_port", type=str, help='P2P port')
    parser.add_argument('--rpc-prot', dest="rpc_port", type=str, help='RPC port')
    parser.add_argument('--interval', dest="snapshot_interval", type=str, help='Snapshot interval value')

    args = parser.parse_args()
    ctx = cvutils.get_ctx(args)

    exit_code = main(ctx)

    exit(exit_code)