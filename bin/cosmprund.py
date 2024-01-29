#!/usr/bin/env python3

import os
import sys
import select
import subprocess
import logging
import cvutils
import argparse

# shell command to prune data directory
def main(args: argparse.Namespace) -> int:
    ctx = cvutils.get_ctx(args)
    data_dir = ctx["data_dir"]
    
    command = ["/usr/local/bin/cosmprund", "prune", data_dir]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    # Keep reading from the process's output pipes in real-time
    while True:
        # Use select to wait for output on either stdout or stderr
        reads = [process.stdout.fileno(), process.stderr.fileno()]
        ret = select.select(reads, [], [])

        for fd in ret[0]:
            if fd == process.stdout.fileno():
                read = process.stdout.readline()
                logging.error(read.strip())
            if fd == process.stderr.fileno():
                read = process.stderr.readline()
                logging.error(read.strip())

        # Break from the loop if the process is done
        if process.poll() is not None:
            break
    return 0
        
if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    profile = os.environ.get("PROFILE")
    if profile == "archive":
        logging.error("This script is blocked on archive nodes")
        exit(1)
    

    parser = argparse.ArgumentParser(description='Load data from image snapshot.')
    parser.add_argument('-d', '--data-dir', dest="data_dir", type=str, help='Data Directory')
    args = parser.parse_args()
    exit_code = main(args)
    exit(exit_code)