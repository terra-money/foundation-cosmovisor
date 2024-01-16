#!/usr/bin/env python3

import time
import snapshot
import cvcontrol
import logging
import schedule
from cvutils import (
    get_ctx,
)

def take_snapshot(snapshots_dir, data_dir, cosmprund_enabled):
    try:
        logging.info(f"Creating lz4 snapshot")
        cvcontrol.stop_process('cosmovisor')
        snapshot.create_snapshot(snapshots_dir, data_dir, cosmprund_enabled)
        cvcontrol.start_process('cosmovisor')
        logging.info(f"Finished lz4 snapshot")
    except Exception as e:
        logging.error(f"Failed to creat snapshot")


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    ctx = get_ctx()
    snapshots_dir = ctx.get("snapshots_dir")
    data_dir = ctx.get("data_dir")
    cosmprund_enabled = ctx.get("cosmprund_enabled")
    schedule.every().day.at("17:00", "US/Central").do(take_snapshot, snapshots_dir, data_dir, cosmprund_enabled)
    while True:
        schedule.run_pending()
        time.sleep(600)