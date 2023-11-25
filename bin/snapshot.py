#!/usr/bin/env python3

import argparse
import os
import time
import cvutils
import cvcontrol
import cosmprund
import shutil
import zipfile
import tarfile
import lz4.frame
import initversion
import logging


import subprocess

def download_file(url: str, destination: str) -> None:
    """
    Downloads a file from a URL and saves it to a destination using aria2c.

    :param url: URL to download the file from.
    :param destination: Destination to save the downloaded file.
    """
    subprocess.run(['aria2c', '-s16', '-x16', '-d', os.path.dirname(destination), '-o', os.path.basename(destination), url])



def remove_first_directory(full_path: str) -> str:
    """
    Removes the first directory from a given path.

    :param full_path: Path to remove the first directory from.
    :return: The path with the first directory removed.
    """
    parts = full_path.split(os.sep)
    relative_path = os.path.join(*parts[2:])
    return relative_path


def exclude_function(tarinfo: tarfile.TarInfo, exclude_patterns: list) -> tarfile.TarInfo:
    """
    Checks if a file should be excluded from a tarball.

    :param tarinfo: TarInfo object representing the file to check.
    :param exclude_patterns: List of patterns to exclude.
    :return: The TarInfo object if it should not be excluded, otherwise None.
    """
    for pattern in exclude_patterns:
        if tarinfo.name.startswith(pattern):
            return None
    return tarinfo


def compress_lz4(filename: str, directories_to_tar: list, exclude_patterns: list) -> None:
    """
    Creates a tarball of the given directories and compresses it using LZ4.

    :param filename: Name of the file to create.
    :param directories_to_tar: List of directories to include in the tarball.
    :param exclude_patterns: List of patterns to exclude from the tarball.
    """
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


def extract_file(filepath: str, extract_to: str) -> bool:
    """
    Extracts a file to a given directory.

    :param filepath: Path to the file to extract.
    :param extract_to: Directory to extract the file to.
    :return: True if the file was successfully extracted, False otherwise.
    """
    if filepath.endswith(('.zip', '.tar.gz', '.tar.lz4')):
        if filepath.endswith('.zip'):
            with zipfile.ZipFile(filepath, 'r') as zip_ref:
                zip_ref.extractall(extract_to)
        elif filepath.endswith('.tar.gz'):
            with tarfile.open(filepath, 'r:gz') as tar_ref:
                tar_ref.extractall(extract_to)
        elif filepath.endswith('.tar.lz4'):
            with lz4.frame.open(filepath, 'rb') as lz4_ref:
                with tarfile.open(fileobj=lz4_ref) as tar_ref:
                    tar_ref.extractall(extract_to)
        return True
    logging.error("Unsupported file format")
    return False


def create_snapshot(ctx, snapshots_dir: str, data_dir: str, cosmprund_enabled: str = False) -> None:
    """
    Creates a snapshot of the given directories.

    :param snapshots_dir: Directory to save the snapshot in.
    :param data_dir: Directory containing the data to include in the snapshot.
    :param inside_wasm_dir: Directory containing the inside wasm data to include in the snapshot.
    :param outside_wasm_dir: Directory containing the outside wasm data to include in the snapshot.
    """
    
    if cosmprund_enabled:
        cosmprund.main(data_dir)

    inside_wasm_dir = os.path.join(data_dir, 'wasm')
    outside_wasm_dir = os.path.join(os.path.dirname(data_dir), 'wasm')
    
    os.makedirs(snapshots_dir, exist_ok=True)
    timestr = time.strftime("%Y%m%d-%H%M%S")
    snapshot_file = f'{snapshots_dir}/snapshot-{timestr}.tar.lz4'
    wasm_file = f'{snapshots_dir}/wasm-{timestr}.tar.lz4'

    if os.path.exists(outside_wasm_dir):
        compress_lz4(snapshot_file, [data_dir, outside_wasm_dir], ['wasm/wasm/cache'])
        compress_lz4(wasm_file, [outside_wasm_dir], ['wasm/wasm/cache'])
    elif os.path.exists(inside_wasm_dir):
        compress_lz4(snapshot_file, [data_dir], ['data/wasm/cache'])
        compress_lz4(wasm_file, [inside_wasm_dir], ['wasm/wasm/cache'])
    else:
        compress_lz4(snapshot_file, [data_dir], [])

    snapshot_latest = f'{snapshots_dir}/snapshot-latest.tar.lz4'
    os.remove(snapshot_latest)
    os.symlink(snapshot_file, snapshot_latest)

    wasm_latest = f'{snapshots_dir}/wasm-latest.tar.lz4'
    os.remove(wasm_latest)
    os.symlink(wasm_file, wasm_latest)


def restore_snapshot(snapshot_url: str, snapshots_dir: str, chain_home: str) -> int:
    """
    Restores a snapshot from a given URL.

    :param snapshot_url: URL of the snapshot to restore.
    :param snapshots_dir: Directory containing the snapshots.
    :param chain_home: Directory to extract the snapshot to.
    :return: 0 if the snapshot was successfully restored, 1 otherwise.
    """
    if snapshot_url:
        snapfn = os.path.basename(snapshot_url.split('?')[0])
        snapfile = os.path.join(snapshots_dir, snapfn)

        if not snapshot_url.startswith('file://'):
            logging.info(f"Downloading snapshot from {snapshot_url}")
            download_file(snapshot_url, snapfile)
        elif snapshot_url[len('file://'):] != snapfile:
            shutil.copy(snapshot_url[len('file://'):], snapfile)

        logging.info(f"Extracting {snapfn} to {chain_home}")
        if not extract_file(snapfile, chain_home):
            return 1

        # Get the owner and group of the chain_home directory
        stat_info = os.stat(chain_home)
        uid = stat_info.st_uid
        gid = stat_info.st_gid

        # Change the owner and group of the extracted files
        for root, dirs, files in os.walk(chain_home):
            dirs.remove('shared')
            for name in dirs + files:
                os.chown(os.path.join(root, name), uid, gid)

        initversion.main(cvutils.get_ctx())
    return 0


def main(args: argparse.Namespace) -> int:
    """
    Main function to create or restore a snapshot.

    :param args: Command line arguments.
    :return: 0 if the snapshot was successfully created or restored, 1 otherwise.
    """
    cvcontrol.stop_process('cosmovisor')

    if args.action == 'create':
        create_snapshot(args.snapshots_dir, args.data_dir, args.cosmprund_enabled)
    elif args.action == 'restore':
        restore_snapshot(args.snapshot_url, args.snapshots_dir, args.chain_home)
    else:
        raise ValueError(f"Unsupported action: {args.action}")

    cvcontrol.start_process('cosmovisor')
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    user_home = os.path.expanduser('~')
    chain_home = os.environ.get('CHAIN_HOME', user_home)
    default_data_dir = os.path.join(chain_home, 'data')
    data_dir = os.environ.get('DATA_DIR', default_data_dir)
    shared_snapshots_dir = os.path.join(os.path.dirname(data_dir), 'shared', 'snapshots')
    default_snapshots_dir = os.environ.get('SNAPSHOTS_DIR', shared_snapshots_dir)
    default_cosmprund_enabled = os.getenv('COSMPRUND_ENABLED', 'false').lower() in ['true', '1', 'yes']
    default_snapshot_url = os.getenv('SNAPSHOT_URL', f'file://{default_snapshots_dir}/snapshot-latest.tar.lz4')

    parser = argparse.ArgumentParser(description='Load data from image snapshot.')
    parser.add_argument('action', type=str, choices=['create', 'restore'], help='Action to perform (create or extract)')
    parser.add_argument('--snapshot_url', type=str, default=default_snapshot_url, help='URL of the snapshot')
    parser.add_argument('--snapshots_dir', type=str, default=default_snapshots_dir, help='Directory to save snapshots')
    parser.add_argument('--chain_home', type=str, default=chain_home, help='Directory to extract snapshots')
    parser.add_argument('--data_dir', type=str, default=data_dir, help='Directory to extract snapshots')
    parser.add_argument('--cosmprund_enabled', action='store_true', default=default_cosmprund_enabled, help='Enable cosmprund')

    args = parser.parse_args()

    exit_code = main(args)
    exit(exit_code)
