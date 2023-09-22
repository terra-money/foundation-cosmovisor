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
    codebase_data = getchaininfo.get_codebase_data(ctx)
    ctx['daemon_name'] = codebase_data.get("daemon_name", ctx["daemon_name"])
    for version in codebase_data["versions"]:
        v = cvutils.get_arch_version(ctx, codebase_data, version)
        cvutils.create_cv_upgrade(ctx, v, False)

def download_libraries(ctx):
    codebase_data = getchaininfo.get_codebase_data(ctx)
    library_urls = codebase_data.get("libraries", [])
    if library_urls:
        for url in library_urls:
            logging.info(f"Downloading library: {url}...")
            urlretrieve(url, filename=f"/usr/lib/{os.path.basename(url)}")

if __name__ == "__main__":
    ctx = cvutils.get_ctx()
    download_versions(ctx)
    download_libraries(ctx)
