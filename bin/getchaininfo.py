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
    chain_json_url = ctx.get('chain_json_url', None)
    daemon_home = ctx.get('daemon_home', os.getcwd())
    if not chain_json_url and chain_name:
        if chain_name == 'terra':
            chain_name = 'terra2'
        elif chain_name == 'terraclassic':
            chain_name = 'terra'
        chain_json_url = f'https://raw.githubusercontent.com/cosmos/chain-registry/master/{chain_name}/chain.json'

    if not chain_json_url:
        print("CHAIN_JSON_URL is not set. Exiting...")
        exit(1)
        
    print(f"Retrieving chain information from {chain_json_url}...")
    
    chain_json_path = os.path.join(daemon_home, 'chain.json')
    response = requests.get(chain_json_url)
    with open(chain_json_path, 'wb') as f:
        f.write(response.content)

def get_upgrades_json(ctx, upgrades_json_path):
    with open(upgrades_json_path, 'r') as f:
        upgrades_data = json.load(f)
    return upgrades_data

def get_upgrades_yaml(ctx, upgrades_yaml_path):
    with open(upgrades_yaml_path, 'r') as f:
        upgrades_data = yaml.safe_load(f)  
    return upgrades_data

def get_upgrades_data(ctx):
    daemon_home = ctx.get('daemon_home', os.getcwd())
    upgrades_yaml_path = ctx.get('upgrades_yaml_path', os.path.join(daemon_home, 'upgrades.yml'))
    if os.path.exists(upgrades_yaml_path):
        return get_upgrades_yaml(ctx, upgrades_yaml_path)
    upgrades_json_path = ctx.get('upgrades_json_path', os.path.join(daemon_home, 'upgrades.json'))
    if os.path.exists(upgrades_json_path):
        return get_upgrades_json(ctx, upgrades_json_path)
    chain_json_path = ctx.get('chain_json_path', os.path.join(daemon_home, 'chain.json'))
    if not os.path.exists(chain_json_path):
        get_chain_json(ctx)
        
    with open(chain_json_path, 'r') as f:
        chain_data = json.load(f)

    return {
        'chain_name': chain_data.get('chain_name', ctx.get('chain_name', '')),
        'daemon_name': chain_data.get('daemon_name', ctx.get('daemon_name', '')),
        'network_type': chain_data.get('network_type', 'mainnet'),
        'libraries': [],
        'versions': chain_data.get('codebase', {}).get('versions', [])
    }

def get_chain_json_version(ctx, version):
    data = get_upgrades_data(ctx)
    
    for v in data['versions']:
        binary_url = None
        if 'tag' in v and v['tag'] == version:
            binaries = v.get('binaries', {})
            binary_url = binaries.get(ctx["arch"], None)
        elif 'name' in v and v['name'] == version:
            binaries = v.get('binaries', {})
            binary_url = binaries.get(ctx["arch"], None)
        elif 'recommended_version' in v and v['recommended_version'] == version:
            binaries = v.get('binaries', {})
            binary_url = binaries.get(ctx["arch"], None)
        if binary_url:
            return {
                "name": v['name'],
                "binary_url": binary_url,
            }

    return None

def get_chain_json_last_version(ctx):
    logging.info(f"Retrieving last available version identified in {ctx['chain_json_path']}...")
    chain_data = get_upgrades_data(ctx)

    last_version = next(reversed(chain_data['versions']), None)
    if last_version:
        binaries = last_version.get('binaries', {})
        binary_url = binaries.get(ctx["arch"], None)
        if binary_url:
            return {
                "name": last_version['name'],
                "binary_url": binary_url,
            }
    return None

def get_chain_json_first_version(ctx):
    logging.info(f"Retrieving first available version identified in {ctx['chain_json_path']}...")
    chain_data = get_upgrades_data(ctx)

    first_version = next(iter(chain_data['versions']), None)
    if first_version:
        binaries = first_version.get('binaries', {})
        binary_url = binaries.get(ctx["arch"], None)
        if binary_url:
            return {
                "name": first_version['name'],
                "binary_url": binary_url,
            }
    return None

def get_chain_json_genesis_version(ctx):
    with open(ctx["chain_json_path"], 'r') as f:
        chain_data = json.load(f)
        codebase = chain_data.get('codebase', {})
        genesis = codebase.get('genesis', {})
        genesis_version = genesis.get('version', None)
        logging.info(f"Retrieving genesis version identified in {ctx['chain_json_path']}...")
        if genesis_version:
            return get_chain_json_version(genesis_version)

    logging.info(f"Genesis version not found in {ctx['chain_json_path']}, falling back to first version...")
    return get_chain_json_first_version(ctx)

def get_chain_json_recommended_version(ctx):
    with open(ctx["chain_json_path"], 'r') as f:
        chain_data = json.load(f)
        codebase = chain_data.get('codebase', {})
        recommended_version = codebase.get('recommended_version', None)
        logging.info(f"Retrieving recommended version identified in {ctx['chain_json_path']}...")
        if recommended_version:
            return get_chain_json_version(ctx, recommended_version)

    logging.info(f"Recommended version not found in {ctx['chain_json_path']}, falling back to last version...")
    return get_chain_json_last_version()

if __name__ == "__main__":
    ctx = cvutils.get_ctx()
    get_chain_json(ctx)