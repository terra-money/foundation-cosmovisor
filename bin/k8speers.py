#!/usr/bin/env python3

import os
import argparse
import requests
import tomlkit
import logging
import socket
import ipaddress
from cvutils import (
    get_ctx
)

def is_running_in_k8s():
    return "KUBERNETES_SERVICE_HOST" in os.environ


def get_service_host_values(filter):
    # Filter environment variables for those containing `filter` and 'PORT_26656_TCP_ADDR'
    filtered_vars = {k: v for k, v in os.environ.items() if filter.upper() in k and 'PORT_26656_TCP_ADDR' in k}

    # Extract the values of these variables
    values = list(filtered_vars.values())

    return values


def get_ip_address(input_str):
    try:
        # Check if the input is a valid IP address
        ipaddress.ip_address(input_str)
        return input_str  # It's already a valid IP address
    except ValueError:
        # If not a valid IP address, try to resolve it as a hostname
        try:
            return socket.gethostbyname(input_str)
        except socket.gaierror:
            raise ValueError(f"Invalid IP address or hostname: {input_str}")
        

# Function to query a DNS name and get the node ID
def get_node_id(host):
    url = f"http://{host}:26657/status"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        id = data["result"]["node_info"]["id"]
        ip = get_ip_address(host)
        return f"{id}@{ip}:26656"
    except requests.RequestException as e:
        logging.error(f"Error querying {host}: {e}")
        return None

# Function to add node IDs as persistent peers in config.toml
def add_persistent_peers(config_file, node_ids):
    try:
        with open(config_file, "r") as file:
            config = tomlkit.parse(file.read())

        persistent_peers = config.get("p2p", {}).get("persistent_peers", "")
        updated_peers = ",".join([persistent_peers] + node_ids)
        
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
    args = parser.parse_args()
    ctx = get_ctx(args)
    node_ips = get_service_host_values(ctx["chain_name"])
    node_ids = [get_node_id(ip) for ip in node_ips]
    node_ids = [id for id in node_ids if id is not None]  # Filter out None values

    add_persistent_peers(ctx["config_toml"], node_ids)
