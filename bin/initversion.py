#!/usr/bin/env python3

import os
import json
import logging
import requests
import argparse
import subprocess
from cvutils import (
    get_ctx,
    get_arch_version,
    create_cv_upgrade, 
)
from getchaininfo import (
    get_codebase_data,
    get_chain_json_version,
    get_chain_json_latest_version,
    get_chain_json_genesis_version,
)

def rsync_cosmovisor(ctx):
    source = "/opt/cosmovisor/" # set in dockerfile
    destination = ctx["cosmovisor_dir"]
    command = ["rsync", "-avz", source, destination]
    subprocess.run(command)


def get_status_version(ctx):
    logging.info(f"Looking for height in {ctx['status_json']}...")

    with open(ctx['status_json'], 'r') as f:
        status = json.load(f)
        height = status['result']['sync_info']['latest_block_height']
        return get_version_at_height(ctx, int(height))


def get_version_at_height(ctx: dict, height: int) -> None:
    logging.info(f"Looking for verison at {height}...")
    codebase_data = get_codebase_data(ctx)

    # Extract versions
    versions = codebase_data['versions']

    # Filter versions that have a 'height' key and sort them by height
    filtered_versions = [v for v in versions if 'height' in v and v['height']]
    sorted_versions = sorted(filtered_versions, key=lambda x: int(x['height']), reverse=True)



    # Find the correct version
    for version in sorted_versions:
        if int(version['height']) <= height:
            return get_arch_version(ctx, codebase_data, version)

    return None


def get_upgrade_info_version(ctx):
    logging.info(f"Downloading binary identified in {ctx['upgrade_info_json']}...")

    with open(ctx['upgrade_info_json'], 'r') as f:
        data = json.load(f)
        name = data.get('name', '')
        logging.info(f"upgrade name is {name}")
        info = data.get('info', '').rstrip(',')
        info = info.replace("'", '"')
        logging.info(f"upgrade info is {info}")
        if isinstance(info, str):
            if info.endswith('.json'):
                response = requests.get(info)
                info = response.json()
            elif 'binaries' in info:
                info = json.loads(info)
            elif isinstance(info, str):
                return {"name": name, "binary_url": info}
            binaries = info.get('binaries', {})
            binary_url = binaries.get(ctx["arch"], None)
            return {"name": name, "binary_url": binary_url}
    return None


def main(ctx):
    version = None
    data_dir = ctx.get("data_dir")
    status_json = ctx.get("status_json")
    upgrade_info_json = ctx.get("upgrade_info_json")
    binary_url = os.environ.get("BINARY_URL")
    binary_version = os.environ.get("BINARY_VERSION")
    
    if binary_url:
        version_name = binary_version if binary_version else "custom"
        version = { "name": version_name, "binary_url": binary_url }
    elif binary_version:
        logging.info("Preparing version defined with environment variables...")
        version = get_chain_json_version(ctx, binary_version)
    elif os.path.exists(upgrade_info_json):
        logging.info("Existing upgrade_info.json found, using upgrade version.")
        version = get_upgrade_info_version(ctx)
    elif os.path.exists(status_json):
        logging.info("Existing upgrade_info.json found, using upgrade version.")
        version = get_status_version(ctx)
    elif os.path.exists(data_dir):
        logging.info("Data dir exists, assuming latest version.")
        # version = getchaininfo.get_chain_json_recommended_version(ctx)
        version = get_chain_json_latest_version(ctx)
    elif ctx.get("statesync_enabled", False):
        logging.info("Statesync enabled using latest version.")
        # version = getchaininfo.get_chain_json_recommended_version(ctx)
        version = get_chain_json_latest_version(ctx)
    elif ctx.get("restore_snapshot", False):
        logging.info("Restore snapshot enabled using latest version.")
        # version = getchaininfo.get_chain_json_recommended_version(ctx)
        version = get_chain_json_latest_version(ctx)
    else:
        logging.info("Preparing genesis version...")
        version = get_chain_json_genesis_version(ctx)

    if version:
        create_cv_upgrade(ctx, version)

    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser(description='Load data from image snapshot.')
    args = parser.parse_args()
    ctx = get_ctx(args)
    rsync_cosmovisor(ctx)
    logging.info("Initializing version...")
    exit_code = main(ctx)
    exit(exit_code)
