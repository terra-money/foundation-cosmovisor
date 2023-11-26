#! /usr/bin/env python3

import sys
import json
import requests
import argparse
import logging

def get_status(rpc_url):
    """
    Sends an HTTP GET request to the specified URL and returns the response in JSON format.
    If an HTTP error occurs, the error message is printed to stderr and None is returned.
    """
    try:
        response = requests.get(rpc_url, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as http_err:
        print(f"HTTP error occurred: {http_err}", file=sys.stderr)
    except requests.exceptions.RequestException as err:
        print(f"An error occurred: {err}", file=sys.stderr)
    return None

def get_id(status):
    return status['result']['node_info']['id']

def get_moniker(status):
    return status['result']['node_info']['moniker']

def get_network(status):
    return status['result']['node_info']['network']

def get_latest_block_height(status):
    return status['result']['sync_info']['latest_block_height']

def get_earliest_block_height(status):
    return status['result']['sync_info']['earliest_block_height']

def get_catching_up(status):
    return str(status['result']['sync_info']['catching_up'])


def is_catching_up(status):
    """
    This function checks if the node is catching up with the network.
    """
    return status['result']['sync_info']['catching_up'] == True


def main(args):
    status = get_status(args.rpc_url)
    if status is not None:
        # Print the values based on the command-line arguments
        if args.id:
            print(get_id(status))
        elif args.moniker:
            print(get_moniker(status))
        elif args.network:
            print(get_network(status))
        elif args.latest_block_height:
            print(get_latest_block_height(status))
        elif args.earliest_block_height:
            print(get_earliest_block_height(status))
        elif args.catching_up:
            print(get_catching_up(status))
        else:
            print(json.dumps(status, indent=4))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(description='Load data from image snapshot.')

    # Add command-line arguments for each function
    parser.add_argument('-u', '--url', dest='rpc_url', default='http://localhost:26657/status', action='store_true', help='Get the ID')
    parser.add_argument('-i', '--id', dest='id', action='store_true', help='Get the ID')
    parser.add_argument('-m', '--moniker', dest='moniker', action='store_true', help='Get the Moniker')
    parser.add_argument('-n', '--network', dest='network', action='store_true', help='Get the Network')
    parser.add_argument('-l', '--latest-block-height', dest='latest_block_height', action='store_true', help='Get the Latest Block Height')
    parser.add_argument('-e', '--earliest-block-height', dest='earliest_block_height', action='store_true', help='Get the Earliest Block Height')
    parser.add_argument('-c', '--catching-up', dest='catching_up', action='store_true', help='Get Catching Up')

    args = parser.parse_args()

    main(args)