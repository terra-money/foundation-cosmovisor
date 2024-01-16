#!/usr/bin/env python3

import re
import json
import tomlkit
import argparse
import logging
from cvutils import (
    get_ctx
)


def parse_unbonding_period(ctx):
    genesis_file_path = ctx.get("genesis_file")

    # Load genesis file
    with open(genesis_file_path, 'r') as file:
        genesis_data = json.load(file)
    
    unbonding_time_str = genesis_data['app_state']['staking']['params']['unbonding_time']

    # Default unbonding time in seconds
    unbonding_time_seconds = 0

    # Extract the number and the unit (s, h, d)
    number = int(re.search(r'\d+', unbonding_time_str).group())
    unit = re.search(r'[a-z]+', unbonding_time_str).group()

    if unit == 's':
        unbonding_time_seconds = number
    elif unit == 'm':
        unbonding_time_seconds = number * 60  # Convert minutes to seconds
    elif unit == 'h':
        unbonding_time_seconds = number * 3600  # Convert hours to seconds
    elif unit == 'd':
        unbonding_time_seconds = number * 86400  # Convert days to seconds
    else:
        raise ValueError("Unknown time unit in unbonding_time")

    # Return the unbonding time in seconds only if it is greater than 0
    if unbonding_time_seconds > 0:
        return unbonding_time_seconds


def calculate_min_retain_blocks(unbonding_period_seconds, mean_block_time, days_to_retain):
    # Calculate the number of blocks for the unbonding period
    unbonding_blocks = unbonding_period_seconds // mean_block_time

    # Initialize days_blocks to 0
    days_blocks = 0

    # Calculate the number of blocks for the specified days, only if DAYS_TO_RETAIN is defined and greater than 0
    if days_to_retain > 0:
        days_blocks = days_to_retain * 86400 // mean_block_time # 86400 seconds per day

    # Choose the larger value between unbonding blocks and days blocks
    max_blocks = max(unbonding_blocks, days_blocks)

    # Set safety_margin to 25% of max_blocks
    safety_margin = max_blocks // 4

    # Add a safety margin
    return max_blocks + safety_margin


def nothing_profile(ctx):
    return {
        'pruning': 'nothing',
        'pruning-interval': 0,
        'pruning-keep-recent': 0,
        'pruning-keep-every': 0,
        'min-retain-blocks': 0,
        'indexer': 'kv',
    }

def custom_profile(ctx, days_to_retain, indexer='kv'):
    unbonding_period = parse_unbonding_period(ctx)
    mean_block_time = ctx.get("mean_block_time")
    return {
        'pruning': 'custom',
        'pruning-interval': 10,
        'pruning-keep-recent': days_to_retain * 86400 // mean_block_time,
        'pruning-keep-every': ctx.get("snapshot_interval", 1000),
        'min-retain-blocks': calculate_min_retain_blocks(unbonding_period, mean_block_time, days_to_retain),
        'indexer': indexer
    }

def get_pruning_settings(ctx):
    profile = ctx.get("profile")
    logging.info(f"Retrieving pruning settings for `{profile}` profile...")
    
    if profile == 'default':
        return nothing_profile(ctx)
    elif profile == 'archive':
        return nothing_profile(ctx)
    elif profile == 'sync':
        return custom_profile(ctx, 0)
    elif profile == 'read':
        return custom_profile(ctx, 0)
    elif profile == 'write':
        return custom_profile(ctx, 1, 'null')
    elif profile == 'snap':
        return custom_profile(ctx, 1, 'null')
    else:
        raise ValueError(f"Unknown profile: {profile}")


def set_pruning(ctx, pruning):
    app_toml_path = ctx.get("app_toml")
    config_toml_path = ctx.get("config_toml")
    
    # Modify app_toml
    with open(app_toml_path, 'r') as file:
        app_toml_data = tomlkit.load(file)
    
    for key in pruning:
        if key in app_toml_data.keys():
            app_toml_data[key] = pruning[key]

    with open(app_toml_path, 'w') as file:
        tomlkit.dump(app_toml_data, file)

    with open(config_toml_path, 'r') as file:
        config_toml_data = tomlkit.load(file)
        if config_toml_data['tx_index']:
            config_toml_data['tx_index']['indexer'] = pruning['indexer']

    with open(config_toml_path, 'w') as file:
        tomlkit.dump(config_toml_data, file)

        
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser(description="Set pruning configuration for TOML files.")

    parser.add_argument("-a", "--app-toml", dest="app_toml", type=str, help="Path to the app TOML file")
    parser.add_argument('-t', '--config-toml', dest="config_toml", type=str, help='Config.toml')
    parser.add_argument("-p", "--profile", type=str, default="", help="Pruning profile")
    parser.add_argument("-m", "--mean-block-period", dest="mean_block_period", type=int, help="Mean block period")
    parser.add_argument("-i", "--snapshot-interval", dest="snapshot_interval", type=int, help="Mean block period")

    args = parser.parse_args()
    ctx = get_ctx(args)
    
    pruning = get_pruning_settings(ctx)
    logging.info(f"setting pruning settings to {pruning}")
    set_pruning(ctx, pruning)
