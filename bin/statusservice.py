#!/usr/bin/env python3

import os
import json
import time
import logging
import schedule
import requests
import cvcontrol
from rpcstatus import RpcStatus
from cvutils import (
    get_ctx,
)

def update_status_json(ctx):
    try:
        logging.info(f"Checking status at {ctx['status_url']}")
        status = RpcStatus(ctx["status_url"])
    except requests.exceptions.ConnectionError:
        logging.error("Connection error, failed to get status")
        return

    try:
        # Write the JSON data to the file
        logging.info(f"Writing status to {ctx['status_json']}")
        with open(ctx["status_json"], 'w') as file:
            json.dump(status.to_dict(), file, indent=4)
    except Exception as e:
        logging.error(f"Failed to write status to {ctx['status_json']}: {e}")
        os.remove(ctx["status_json"])
    
    try:
        if status.is_behind(ctx["chain_name"], ctx["domain"]):
            logging.info(f"Node has fallen behind, restarting cosmovisor...")
            cvcontrol.restart_process("cosmovisor")
    except Exception as e:
        logging.error(f"Failed to get status: {e}")


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    ctx = get_ctx()
    schedule.every(1).minutes.do(update_status_json, ctx)
    while True:
        schedule.run_pending()
        time.sleep(60)