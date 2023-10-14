#!/usr/bin/env python3

import os
import json
import yaml
import requests
import logging
import cvutils

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

def get_chain_json(ctx):
    chain_name = ctx.get('chain_name', None)
    chain_network = ctx.get('chain_network', 'mainnet')
    chain_json_url = ctx.get('chain_json_url', None)
    daemon_home = ctx.get('daemon_home', os.getcwd())
    if not chain_json_url and chain_name:
        if chain_name == 'terra':
            chain_name = 'terra2'
        elif chain_name == 'terraclassic':
            chain_name = 'terra'
        
        if chain_network == 'testnet':
            chain_json_url = f'https://raw.githubusercontent.com/cosmos/chain-registry/master/testnets/{chain_name}testnet/chain.json'
        else:
            chain_json_url = f'https://raw.githubusercontent.com/cosmos/chain-registry/master/{chain_name}/chain.json'

    if not chain_json_url:
        print("CHAIN_JSON_URL is not set. Exiting...")
        exit(1)
        
    print(f"Retrieving chain information from {chain_json_url}...")
    
    chain_json_path = ctx.get('chain_json_path')
    response = requests.get(chain_json_url)
    with open(chain_json_path, 'wb') as f:
        f.write(response.content)

def get_upgrades_json(ctx, upgrades_json_path):
    with open(upgrades_json_path, 'r') as f:
        codebase_data = json.load(f)
    return codebase_data

def get_upgrades_yaml(ctx, upgrades_yaml_path):
    with open(upgrades_yaml_path, 'r') as f:
        codebase_data = yaml.safe_load(f)  
    return codebase_data

def get_codebase_data(ctx):
    upgrades_yaml_path = ctx.get('upgrades_yaml_path')
    if os.path.exists(upgrades_yaml_path):
        logging.info(f"Retrieving codebase data from {upgrades_yaml_path}...")
        return get_upgrades_yaml(ctx, upgrades_yaml_path)
    
    upgrades_json_path = ctx.get('upgrades_json_path') 
    logging.info(f"Retrieving codebase data from {upgrades_json_path}...")
    if os.path.exists(upgrades_json_path):
        logging.info(f"Retrieving codebase data from {upgrades_json_path}...")
        return get_upgrades_json(ctx, upgrades_json_path)
    
    chain_json_path = ctx.get('chain_json_path')
    if not os.path.exists(chain_json_path):
        get_chain_json(ctx)
        
    logging.info(f"Retrieving codebase data from {chain_json_path}...")
    with open(chain_json_path, 'r') as f:
        chain_data = json.load(f)

    return {
        'chain_name': chain_data.get('chain_name', ctx.get('chain_name', '')),
        'daemon_name': chain_data.get('daemon_name', ctx.get('daemon_name', '')),
        'network_type': chain_data.get('network_type', 'mainnet'),
        'git_repo': chain_data.get('git_repo', ''),
        'libraries': [],
        'versions': chain_data.get('codebase', {}).get('versions', [])
    }
    
def get_chain_json_version(ctx, version):
    data = get_codebase_data(ctx)
    
    for v in data['versions']:
        if 'tag' in v and v['tag'] == version:
            return cvutils.get_arch_version(ctx, data, v)
        elif 'name' in v and v['name'] == version:
            return cvutils.get_arch_version(ctx, data, v)
        elif 'recommended_version' in v and v['recommended_version'] == version:
            return cvutils.get_arch_version(ctx, data, v)

    return None

def get_chain_json_last_version(ctx):
    logging.info(f"Retrieving last available version identified in {ctx['chain_json_path']}...")
    codebase_data = get_codebase_data(ctx)

    last_version = next(reversed(codebase_data['versions']), None)
    if last_version:
        return cvutils.get_arch_version(ctx, codebase_data, last_version)
    return None

def get_chain_json_first_version(ctx):
    logging.info(f"Retrieving first available version identified in {ctx['chain_json_path']}...")
    codebase_data = get_codebase_data(ctx)

    first_version = next(iter(codebase_data['versions']), None)
    if first_version:
        return cvutils.get_arch_version(ctx, codebase_data, first_version)
    return None

def get_chain_json_genesis_version(ctx):
    with open(ctx["chain_json_path"], 'r') as f:
        chain_data = json.load(f)
        codebase_data = chain_data.get('codebase', {})
        genesis = codebase_data.get('genesis', {})
        genesis_version = genesis.get('version', None)
        logging.info(f"Retrieving genesis version identified in {ctx['chain_json_path']}...")
        if genesis_version:
            return get_chain_json_version(genesis_version)

    logging.info(f"Genesis version not found in {ctx['chain_json_path']}, falling back to first version...")
    return get_chain_json_first_version(ctx)

def get_chain_json_recommended_version(ctx):
    with open(ctx["chain_json_path"], 'r') as f:
        chain_data = json.load(f)
        codebase_data = chain_data.get('codebase', {})
        recommended_version = codebase_data.get('recommended_version', None)
        logging.info(f"Retrieving recommended version identified in {ctx['chain_json_path']}...")
        if recommended_version:
            return get_chain_json_version(ctx, recommended_version)

    logging.info(f"Recommended version not found in {ctx['chain_json_path']}, falling back to last version...")
    return get_chain_json_last_version()


if __name__ == "__main__":
    ctx = cvutils.get_ctx()
    get_chain_json(ctx)