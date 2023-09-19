#!/usr/bin/env python3

import os
import logging
import cvutils
import getchaininfo
from urllib.request import urlretrieve

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

def download_versions(ctx):
    upgrades_data = getchaininfo.get_upgrades_data(ctx)
    ctx['daemon_name'] = upgrades_data.get("daemon_name", ctx["daemon_name"])
    for version in upgrades_data["versions"]:
        name = version.get("name", "")
        height = version.get("height", "")
        binary_url = version.get("binaries", {}).get(ctx["arch"], "")
        version = {"name": name, "height": height, "binary_url": binary_url}
        # create_cv_upgrad
        cvutils.create_cv_upgrade(ctx, version, False)

def download_libraries(ctx):
    upgrades_data = getchaininfo.get_upgrades_data(ctx)
    library_urls = upgrades_data.get("libraries", [])
    if library_urls:
        for url in library_urls:
            logging.info(f"Downloading library: {url}...")
            # You might need to adjust the target directory
            urlretrieve(url, filename=f"/usr/local/lib/{os.path.basename(url)}")

if __name__ == "__main__":
    ctx = cvutils.get_ctx()
    download_versions(ctx)
    download_libraries(ctx)