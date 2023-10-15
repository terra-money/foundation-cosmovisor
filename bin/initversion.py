#!/usr/bin/env python3

import os
import sys
import shutil
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


def check_cv_path(ctx, source_path):
    destination_path = f"{ctx['cosmovisor_dir']}/{os.path.basename(source_path)}"
    source_dev = os.stat(source_path).st_dev
    
    # nothing to do if the source does not exist
    if not os.path.exists(source_path):
        return
    
    # Check if the link_path exists
    if not os.path.exists(destination_path):
        destination_dev = os.stat(ctx['cosmovisor_dir']).st_dev
        logging.info(f"Error: Path '{destination_path}' does not exist.")
        if source_dev != destination_dev:
            os.makedirs(destination_path, exist_ok=True)
        else:
            logging.info(f"Creating symbolic link '{source_path}' -> '{destination_path}'...")
            os.symlink(destination_path, source_path)
    
    # dir is link but not pointing to the correct target        
    if os.path.islink(destination_path):
        actual_target = os.readlink(destination_path)
        if actual_target != source_path:
            logging.info(f"Copying '{source_path}' -> '{destination_path}'...")
            shutil.copytree(source_path, destination_path, dirs_exist_ok=True)
            return 

    if source_dev != os.stat(destination_path).st_dev:
        logging.info(f"Copying '{source_path}' -> '{destination_path}'...")
        shutil.copytree(source_path, destination_path, dirs_exist_ok=True)
        return 

def main(ctx):
    os.makedirs(ctx["data_dir"], exist_ok=True)
    os.makedirs(ctx["cosmovisor_dir"], exist_ok=True)
    check_cv_path(ctx, "/opt/cosmovisor/upgrades")
    
    upgrade_info_json_path = os.path.join(ctx["data_dir"], "upgrade-info.json")
    recommended_version = os.environ.get("RECOMMENDED_VERSION", "")
    prefer_recommended_version = os.environ.get("PREFER_RECOMMENDED_VERSION", False)
    state_sync_enabled = os.environ.get("STATE_SYNC_ENABLED", "false")

    version = None
    # we use prefer recommended version here beacause recommended_version is set by chain.json
    # do not make this an or statement or we will cannot sync from genesis
    if (bool(prefer_recommended_version) and recommended_version):
        logging.info("Prefer recommended version is set, using recommended version.")
        version = get_recommended_version(ctx)
    elif state_sync_enabled == "true":
        logging.info("State sync is enabled, using recommended verison.")
        version = get_recommended_version(ctx)
    elif os.path.exists(upgrade_info_json_path):
        logging.info("Existing upgrade_info.json found, using upgrade version.")
        version = cvutils.get_upgrade_info_version(ctx)
    else:
        logging.info("No version overides found, assuming sync from genesis.")
        version = get_genesis_version(ctx)
    
    if version:
        cvutils.create_cv_upgrade(ctx, version)
    else:
        logging.error("No version found. Exiting...")
        sys.exit(1)

if __name__ == "__main__":
    ctx = cvutils.get_ctx()
    main(ctx)