#!/usr/bin/env python3

import os
import sys
import logging
import cvutils
import getchaininfo

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

def get_genesis_version(ctx):
    genesis_binary_url = os.environ.get("GENESIS_BINARY_URL", None)
    if genesis_binary_url:
        logging.info("Preparing genesis version defined with environment variables...")
        return {
            "name": "genesis",
            "binary_url": genesis_binary_url,
        }
    return getchaininfo.get_chain_json_genesis_version(ctx)

def get_recommended_version(ctx):
    recomended_version = os.environ.get("RECOMMENDED_VERSION", None)
    recommended_binary_url = os.environ.get("RECOMMENDED_BINARY_URL", None)
    if recommended_binary_url:
        logging.info("Preparing recommended version defined with environment variables...")
        return {
            "name": recomended_version,
            "binary_url": recommended_binary_url,
        }
    if recomended_version:
        logging.info("Preparing recommended version defined with environment variables...")
        return getchaininfo.get_chain_json_version(ctx, recomended_version)
    return getchaininfo.get_chain_json_recommended_version(ctx)

def main(ctx):
    os.makedirs(ctx["data_dir"], exist_ok=True)
    
    upgrade_info_json_path = os.path.join(ctx["data_dir"], "upgrade_info.json")
    recommended_version = os.environ.get("RECOMMENDED_VERSION", None)
    prefer_recommended_version = os.environ.get("PREFER_RECOMMENDED_VERSION", None)
    state_sync_enabled = os.environ.get("STATE_SYNC_ENABLED", "false")
    
    version = None
    if (prefer_recommended_version == "true" or recommended_version):
        version = get_recommended_version(ctx)
    elif state_sync_enabled == "true":
        version = get_recommended_version(ctx)
    elif os.path.exists(upgrade_info_json_path):
        version = getchaininfo.get_upgrade_info_version(ctx)
    else:
        version = get_genesis_version(ctx)
    
    if version:
        cvutils.create_cv_upgrade(ctx, version)
    else:
        logging.error("No version found. Exiting...")
        sys.exit(1)

if __name__ == "__main__":
    ctx = cvutils.get_ctx()
    main(ctx)