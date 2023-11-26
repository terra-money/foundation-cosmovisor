#!/usr/bin/env python3

import os
import logging
import cvutils
import getchaininfo

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

def main(ctx):
    cvutils.link_cv_path(ctx)

    version = None
    data_dir = ctx.get("data_dir")
    upgrade_info_json = ctx.get("upgrade_info_json")
    binary_url = os.environ.get("BINARY_URL")
    binary_version = os.environ.get("BINARY_VERSION")
    
    if binary_url:
        version_name = binary_version if binary_version else "custom"
        version = { "name": version_name, "binary_url": binary_url }
    elif binary_version:
        logging.info("Preparing version defined with environment variables...")
        version = getchaininfo.get_chain_json_version(ctx, binary_version)
    elif os.path.exists(upgrade_info_json):
        logging.info("Existing upgrade_info.json found, using upgrade version.")
        version = cvutils.get_upgrade_info_version(ctx)
    elif os.path.exists(data_dir):
        logging.info("Data dir exists, assuming latest version.")
        # version = getchaininfo.get_chain_json_recommended_version(ctx)
        version = getchaininfo.get_chain_json_latest_version(ctx)
    else:
        logging.info("Preparing genesis version...")
        version = getchaininfo.get_chain_json_genesis_version(ctx)

    if version:
        cvutils.create_cv_upgrade(ctx, version)

    cvutils.copy_cv_path(ctx)
    # do not exit if version = None, we want to keep the container running
    return 

if __name__ == "__main__":
    ctx = cvutils.get_ctx()
    main(ctx)