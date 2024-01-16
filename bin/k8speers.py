#!/usr/bin/env python3

import argparse
import tomlkit
import logging
import k8sutils
from cvutils import (
    get_ctx
)

# Function to add node IDs as persistent peers in config.toml
def add_persistent_peers(config_file, peers):
    try:
        with open(config_file, "r") as file:
            config = tomlkit.parse(file.read())

        existing_peers = config.get("p2p", {}).get("persistent_peers", "")
        existing_peers_set = set(existing_peers.split(',')) if existing_peers else set()

        # Convert the nodes to a set to remove duplicates and then merge with existing
        peers_set = set(peers)
        updated_peers_set = existing_peers_set.union(peers_set)

        # Convert back to a comma-separated string
        updated_peers = ",".join(updated_peers_set)

        print(f"Updated persistent peers: {updated_peers}")

        config["p2p"]["persistent_peers"] = updated_peers

        with open(config_file, "w") as file:
            file.write(tomlkit.dumps(config))

    except Exception as e:
        print(f"Error updating config file: {e}")

    

# Main execution
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser(description='configure k8s peers') 
    parser.add_argument('-n', '--chain-name', dest="chain_name", type=str, help='Chain name')
    parser.add_argument('-t', '--config-toml', dest="config_toml", type=str, help='Config.toml')
    parser.add_argument('-p', '--prefix', dest="prefix", type=str, default="discover", help='Service prefix')
    parser.add_argument('-d', '--domain', dest="domain", type=str, default="chains.svc.cluster.local", help='=Domain name')
    args = parser.parse_args()
    ctx = get_ctx(args)
    
    if k8sutils.is_running_in_k8s():
        peers = k8sutils.get_service_peers(ctx["chain_name"], args.domain)
        add_persistent_peers(ctx["config_toml"], peers)
