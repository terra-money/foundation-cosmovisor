#!/usr/bin/env python3

import os
import subprocess
import argparse
import logging

def main(ctx):
    print("Initializing node from scratch...")
    os.makedirs(ctx.get("data_dir"), exist_ok=True)
    init_command = ["/usr/local/bin/cosmovisor", "run", "init", ctx.get("moniker"), "--home", ctx.get("chain_home"), "--chain-id", ctx.get("chain_name")]
    
    try:
        subprocess.run(init_command, check=True)
        genesis_file = ctx.get("genesis_file")
        if os.path.isfile(genesis_file):
            os.remove(genesis_file)
        else:
            print("Failed to initialize node.")
            exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error: {e}")
        exit(1)

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser(description='Load data from image snapshot.')
    parser.add_argument('-c', '--chain-id', dest="chain_id", type=str, help='Chain id')
    parser.add_argument('-h', '--chain-home', dest="chain_home", type=str, help='Chain home directory')
    parser.add_argument('-d', '--data-dir', dest="data_dir", type=str, help='Data directory')
    parser.add_argument('-m', '--moniker', dest="moniker", type=str, help='Moniker')

    args = parser.parse_args()
    exit_code = main(args)
    exit(exit_code)
