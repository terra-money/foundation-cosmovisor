#!/usr/bin/env python3

import os
import time
import tarfile
import cvcontrol
import cosmprund
import lz4.frame

# Define the home directory
user_home = os.path.expanduser('~')

# Define the chain directory
chain_home = os.environ.get('CHAIN_HOME', user_home)

# Define the data directory
default_data_dir = os.path.join(chain_home, 'data')
data_dir = os.environ.get('DATA_DIR', default_data_dir)

# Define the wasm directory
inside_wasm_dir = os.path.join(data_dir, 'wasm')
outside_wasm_dir = os.path.join(os.path.dirname(data_dir), 'wasm')

# Define the snapshot directory
default_snap_dir = os.path.join(os.path.dirname(data_dir), 'shared', 'snapshots')
snap_dir = os.environ.get('SNAPSHOTS_DIR', default_snap_dir)

def remove_first_directory(full_path):
    # Split the path into parts
    parts = full_path.split(os.sep)

    # Remove the first part (directory)
    relative_path = os.path.join(*parts[2:])

    return relative_path

# Define a function to check if a file should be excluded
def exclude_function(tarinfo, exclude_patterns):
    for pattern in exclude_patterns:
        if tarinfo.name.startswith(pattern):
            return None
    return tarinfo

# Define a function to create the tarball and compress it using LZ4
def compress_lz4(filename, directories_to_tar, exclude_patterns):
    with lz4.frame.open(filename, mode='wb') as lz4_file:
        with tarfile.open(fileobj=lz4_file, mode='w|') as tar:
            for directory in directories_to_tar:
                for root, dirs, files in os.walk(directory):
                    for file in files:
                        file_path = os.path.join(root, file)
                        tar_info = tar.gettarinfo(file_path, arcname=remove_first_directory(file_path))
                        if exclude_function(tar_info, exclude_patterns):
                            with open(file_path, 'rb') as file_obj:
                                tar.addfile(tar_info, file_obj)

# Define a function to create a snapshot
def create_snapshot():
    # Ensure the snapshot directory exists
    os.makedirs(snap_dir, exist_ok=True)
    timestr = time.strftime("%Y%m%d-%H%M%S")
    snapshot_file = f'{snap_dir}/snapshot-{timestr}.tar.lz4'
    wasm_file = f'{snap_dir}/wasm-{timestr}.tar.lz4'

    # Create tar
    if os.path.exists(outside_wasm_dir):
        compress_lz4(snapshot_file, [data_dir, outside_wasm_dir], ['wasm/wasm/cache'])
        compress_lz4(wasm_file, [outside_wasm_dir], ['wasm/wasm/cache'])
    elif os.path.exists(inside_wasm_dir):
        compress_lz4(snapshot_file, [data_dir], ['data/wasm/cache'])
        compress_lz4(wasm_file, [inside_wasm_dir], ['wasm/wasm/cache'])
    else:
        compress_lz4(snapshot_file, [data_dir], [])
        
    # Create a symlink to the latest snapshot
    snapshot_latest = f'{snap_dir}/snapshot-latest.tar.lz4'
    os.remove(snapshot_latest)
    os.symlink(snapshot_file, snapshot_latest)

    # Create a symlink to the latest wasm snapshot
    wasm_latest = f'{snap_dir}/wasm-latest.tar.lz4'
    os.remove(wasm_latest)
    os.symlink(wasm_file, wasm_latest)

def main():
    # Stop the cosmovisor process
    cvcontrol.stop_process('cosmovisor')

    # Prune the data directory
    # Safety to prevent pruning if not desired
    if os.environ.get('COSMPRUND_ENABLED') == 'true':
        cosmprund.main(data_dir)

    # Create a snapshot
    create_snapshot()

    # Start the cosmovisor process
    cvcontrol.start_process('cosmovisor')

if __name__ == '__main__':
    main()
