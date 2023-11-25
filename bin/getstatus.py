#! /usr/bin/env python3

import sys
import json
import requests

def get_status():
    """
    Sends an HTTP GET request to the specified URL and returns the response in JSON format.
    If an HTTP error occurs, the error message is printed to stderr and None is returned.
    """
    try:
        rpc_url = 'http://localhost:26657/status'
        response = requests.get(rpc_url, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as http_err:
        print(f"HTTP error occurred: {http_err}", file=sys.stderr)
    except requests.exceptions.RequestException as err:
        print(f"An error occurred: {err}", file=sys.stderr)
    return None


def is_catching_up():
    """
    This function checks if the node is catching up with the network.
    """
    status = get_status()
    if status is not None:
        return status['result']['sync_info']['catching_up'] == True
    return True


def main():
    status = get_status()
    print(json.dumps(status, indent=4))


if __name__ == "__main__":
    main()