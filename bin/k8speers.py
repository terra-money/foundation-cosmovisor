#!/usr/bin/env python3

import argparse
import logging
import k8sutils
from cvutils import (
    get_ctx
)

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
        k8sutils.add_persistent_peers(ctx)
