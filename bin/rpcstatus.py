#!/usr/bin/env python3

import json
import requests
import argparse
import k8sutils
import logging


class DictToObject:
    def __init__(self, dictionary):
        for key, value in dictionary.items():
            if isinstance(value, dict):
                value = DictToObject(value)
            setattr(self, key, value)

    def to_dict(self):
        return self.__dict__


class RpcStatus:
    def __init__(self, rpc_url):
        if rpc_url.startswith('file://'):
            with open(rpc_url[7:], 'r') as f:
                self._data = json.load(f)
        else:
            response = requests.get(rpc_url, timeout=3)
            response.raise_for_status()
            self._data = response.json()
            
        result = self._data.get('result', self._data)
        for key, value in result.items():
            if isinstance(value, dict):
                value = DictToObject(value)
            setattr(self, key, value)

    def is_catching_up(self):
        catching_up = str(self.sync_info.catching_up)
        return catching_up.lower() == 'true' or catching_up == '1'
    

    def is_behind(self, chain, domain):
        """
        This function checks for the condition where the block height is behind other nodes
        but the chains software itself does not know it is behind
        """
        # if the chain knows it is catching up return false 
        if self.is_catching_up():
            return False
        
        for remote in k8sutils.get_service_rpc_status(chain, domain):
            if not remote.is_catching_up():
                if int(remote.sync_info.latest_block_height) > (int(self.sync_info.latest_block_height) + int(100)):
                    return True
                
        return False
        
    def to_dict(self):
        return self._data
    
    def json(self):
        return json.dumps(self._data, indent=4)


def main(args):
    status = RpcStatus(args.rpc_url)
    if status is not None:
        # Print the values based on the command-line arguments
        if args.id:
            print(status.node_info.id)
        elif args.moniker:
            print(status.node_info.moniker)
        elif args.network:
            print(status.node_info.network)
        elif args.latest_block_height:
            print(status.sync_info.latest_block_height)
        elif args.earliest_block_height:
            print(status.sync_info.earliest_block_height)
        elif args.catching_up:
            print(status.sync_info.catching_up)
        else:
            print(status.json())


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
