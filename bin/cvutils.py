#!/usr/bin/env python3

import os
import tarfile
import zipfile
import json
import requests
import shutil
import logging

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

def get_ctx():
    arch = get_system_arch()
    debug = os.environ.get("DEBUG", None)
    daemon_home = os.environ.get("DAEMON_HOME", os.getcwd())
    chain_home = os.environ.get("CHAIN_HOME", daemon_home)
    chain_name = os.environ.get('CHAIN_NAME', 'terra')
    daemon_name = os.environ.get("DAEMON_NAME", f"{chain_name}d")
    chain_json_url = os.environ.get('CHAIN_JSON_URL', None)

    chain_json_path = os.path.join(daemon_home, 'chain.json')
    upgrades_json_path = os.path.join(daemon_home, 'upgrades.json')

    cosmovisor_dir = os.path.join(daemon_home, "cosmovisor")
    cv_current_dir = os.path.join(cosmovisor_dir, "current")
    cv_genesis_dir = os.path.join(cosmovisor_dir, "genesis")
    cv_upgrades_dir = os.path.join(cosmovisor_dir, "upgrades")

    data_dir = os.path.join(chain_home, "data")
    config_dir = os.path.join(chain_home, "config")

    return {
        "arch": arch,
        "debug": debug,
        "daemon_home": daemon_home,
        "chain_name": chain_name,
        "daemon_name": daemon_name,
        "chain_json_url": chain_json_url,

        "chain_json_path": chain_json_path,
        "upgrades_json_path": upgrades_json_path,

        "cosmovisor_dir": cosmovisor_dir,
        "cv_current_dir": cv_current_dir,
        "cv_genesis_dir": cv_genesis_dir,
        "cv_upgrades_dir": cv_upgrades_dir,

        "data_dir": data_dir,
        "config_dir": config_dir,
    }

def get_system_arch():
    logging.info("Identifying system architecture...")
    os_name = os.uname().sysname.lower()
    mach = os.uname().machine
    logging.info(f"OS: {os_name}")
    logging.info(f"Machine: {mach}")
    arch = None
    if mach == "arm64":
        arch = f"{os_name}/arm64"
    elif mach == "aarch64":
        arch = f"{os_name}/arm64"
    elif mach == "x86_64":
        arch = f"{os_name}/amd64"
    return arch

def get_arch_version(ctx, codebase, version):
    name = version.get("name", "")
    height = version.get("height", "")
    git_repo = codebase.get("git_repo", "")
    tag = version.get("tag", name)
    recommended_version = version.get("recommended_version", tag)
    binaries = version.get("binaries", {})
    binary_url = binaries.get(ctx["arch"], "")
    return {
        "name": name, 
        "height": height, 
        "tag": tag,
        "git_repo": git_repo, 
        "tag": tag, 
        "recommended_version": recommended_version,
        "binary_url": binary_url,
    }

def create_cv_upgrade(ctx, version, linkCurrent=True):
    os.makedirs(ctx["cv_upgrades_dir"], exist_ok=True)
    daemon_name = ctx.get("daemon_name")
    upgrade_name = version.get("name", "")
    binary_url = version.get("binary_url", {})
    tag = version.get("tag", "")

    upgrade_path = os.path.join(ctx["cv_upgrades_dir"], upgrade_name)
    binary_file = os.path.join(upgrade_path, "bin", daemon_name)

    logging.info(f"Found version {upgrade_name}, Checking for {upgrade_path}...")

    os.makedirs(upgrade_path, exist_ok=True)
    if binary_url:
        download_cv_version(binary_url, binary_file)
        
    if os.path.exists(binary_file):
        if linkCurrent:
            link_cv_current(ctx, upgrade_path)
        if not os.path.exists(ctx["cv_genesis_dir"]):
            link_cv_genesis(ctx, upgrade_path)


def link_cv_current(ctx, upgrade_path):
    cv_current_dir = ctx["cv_current_dir"]
    if os.path.islink(cv_current_dir):
        logging.info(f"Removing existing {cv_current_dir}...")
        os.unlink(cv_current_dir)
    elif os.path.exists(cv_current_dir):
        logging.info(f"Removing existing {cv_current_dir}...")
        shutil.rmtree(cv_current_dir)
    logging.info(f"Linking {cv_current_dir} to {upgrade_path}...")
    os.symlink(upgrade_path, cv_current_dir)


def link_cv_genesis(ctx, upgrade_path):
    cv_genesis_dir = ctx["cv_genesis_dir"]
    if os.path.islink(cv_genesis_dir):
        logging.info(f"Removing existing {cv_genesis_dir}...")
        os.unlink(cv_genesis_dir)
    elif os.path.exists(cv_genesis_dir):
        logging.info(f"Removing existing {cv_genesis_dir}...")
        shutil.rmtree(cv_genesis_dir)
    logging.info(f"Linking {cv_genesis_dir} to {upgrade_path}")
    os.symlink(upgrade_path, cv_genesis_dir)

def download_cv_version(binary_url, binary_file):
    binary_path = os.path.dirname(binary_file)
    binary_url_split = binary_url.split('?')

    if not os.path.exists(binary_file):
        print(f"Downloading {binary_url} to {binary_file}...")
        os.makedirs(binary_path, exist_ok=True)

        if binary_url_split[0].endswith(".tar.gz"):
            response = requests.get(binary_url, stream=True)
            response.raise_for_status()
            with tarfile.open(mode='r|gz', fileobj=response.raw) as tar:
                tar.extractall(path=binary_path)
        elif binary_url_split[0].endswith(".zip"):
            # this code does not work consistently
            response = requests.get(binary_url)
            response.raise_for_status()
            zip_path = os.path.join("/tmp", os.path.basename(binary_url_split[0]))
            logging.error(f"Downloading {binary_url} to {zip_path}...")
            with open(zip_path, 'wb') as f:
                f.write(response.content)
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                for zip_info in zip_ref.infolist():
                    zip_name = zip_info.filename
                    if zip_name.endswith('/'):
                        continue
                    file_content = zip_ref.read(zip_name)
                    file_path = os.path.join(binary_path, os.path.basename(zip_name))
                    logging.info(f"Extract: {zip_name} to {file_path}")
                    with open(file_path, 'wb') as file_handle:
                        file_handle.write(file_content)
            os.remove(zip_path)
        else:
            response = requests.get(binary_url)
            response.raise_for_status()
            with open(binary_file, 'wb') as f:
                f.write(response.content)

    os.chmod(binary_file, 0o755)

    with open(binary_file, 'rb') as f:
        if f.read(1) == b'{':
            with open(binary_file, 'r') as f_json:
                json_data = json.load(f_json)
                arch_binary_url = json_data.get('binaries', {}).get('ARCH', '')
                download_cv_version(arch_binary_url, binary_file)


def get_upgrade_info_version(ctx):
    logging.info(f"Downloading binary identified in {ctx['upgrade_info_json']}...")

    with open(ctx['upgrade_info_json'], 'r') as f:
        data = json.load(f)
        name = data.get('name', '')
        info = data.get('info', '')
        if isinstance(info, str):
            if 'binaries' in info:
                info = json.loads(info)
                binaries = info.get('binaries', {})
                binary_url = binaries.get(ctx["arch"], None)
            elif 'http:' in info:
                binary_url = info
            if binary_url:
                return {"name": name, "binary_url": binary_url}
    return None
