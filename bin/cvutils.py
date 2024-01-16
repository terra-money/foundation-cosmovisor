import os
import tarfile
import zipfile
import json
import requests
import logging
import subprocess
import platform
import shutil
import tempfile
import argparse

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

# modiffication of getattr to return default value if attribute is empty
def agetattr(obj, name, default=None):
    value = getattr(obj, name, default)
    if not value:
        return default
    return value


def get_ctx(args: argparse.Namespace = {}):
    arch = get_system_arch()
    uid = agetattr(args, "uid", 1000)
    gid = agetattr(args, "gid", 1000)
    debug = agetattr(args, "debug", os.environ.get("DEBUG", None))

    moniker = agetattr(args, "moniker", os.environ.get("MONIKER", "rpcnode"))
    chain_network = agetattr(args, "chain_network", os.environ.get("CHAIN_NETWORK", "mainnet"))
    chain_name = agetattr(args, "chain_name", os.environ.get("CHAIN_NAME", chain_name_from_hostname()))
    chain_id = agetattr(args, "chain_name", os.environ.get("CHAIN_NAME", f"{chain_name}-1"))
    daemon_name = agetattr(args, "daemon_name", os.environ.get("DAEMON_NAME", f"{chain_name}d"))
    domain = agetattr(args, "domain", "chains.svc.cluster.local")
    
    daemon_home = agetattr(args, "daemon_home", os.environ.get("DAEMON_HOME", os.getcwd()))
    chain_home = agetattr(args, "chain_home", os.environ.get("CHAIN_HOME", daemon_home))
    chain_json_url = agetattr(args, "chain_json_url", os.environ.get("CHAIN_JSON_URL", None))
    
    chain_json_path = agetattr(args, "chain_json_path", os.environ.get("CHAIN_JSON_PATH", '/etc/default/chain.json'))
    upgrades_yaml_path = agetattr(args, "upgrades_yaml_path", os.environ.get("UPGRADES_YAML_PATH", '/etc/default/upgrades.yml'))
    upgrades_json_path = agetattr(args, "upgrades_json_path", os.environ.get("UPGRADES_JSON_PATH", '/etc/default/upgrades.json'))

    config_dir = agetattr(args, "config_dir", os.path.join(chain_home, "config"))
    genesis_file = agetattr(args, "genesis_file", os.path.join(config_dir, "genesis.json"))
    config_toml = agetattr(args, "config_toml", os.path.join(config_dir, "config.toml"))
    app_toml = agetattr(args, "app_toml", os.path.join(config_dir, "app.toml"))
    addrbook = agetattr(args, "addrbook", os.path.join(config_dir, "addrbook.json"))
    
    data_dir = agetattr(args, "data_dir", os.path.join(chain_home, "data"))
    status_url = agetattr(args, "status_url", "http://127.0.0.1:26657/status")
    status_json = agetattr(args, "status_json", os.path.join(data_dir, "status.json"))
    upgrade_info_json = agetattr(args, "upgrade_info_json", os.path.join(data_dir, "upgrade-info.json"))

    cosmovisor_dir = agetattr(args, "cosmovisor_dir", os.environ.get("COSMOVISOR_DIR", os.path.join(daemon_home, "cosmovisor")))

    profile = agetattr(args, "profile", os.environ.get("PROFILE", "default"))
    mean_block_time = agetattr(args, "mean_block_period", os.environ.get("MEAN_BLOCK_PERIOD", 6))
    snapshot_interval = agetattr(args, "snapshot_interval", os.environ.get("SNAPSHOT_INTERVAL", 1000))


    snapshots_dir = agetattr(args, "snapshots_dir", os.environ.get("SNAPSHOTS_DIR", os.path.join(os.path.dirname(data_dir), "shared", "snapshots")))
    snapshot_url = agetattr(args, "snapshot_url", os.environ.get("SNAPSHOT_URL", f"file://{snapshots_dir}/snapshot-latest.tar.lz4"))
    cosmprund_enabled = agetattr(args, "cosmprund_enabled", os.environ.get("COSMPRUND_ENABLED", "false").lower() in ["true", "1", "yes"])

    statesync_enabled = agetattr(args, "statesync_enabled", os.environ.get("STATE_SYNC_ENABLED", "false").lower() in ["true", "1", "yes"])
    restore_snapshot = agetattr(args, "restore_snapshot", os.environ.get("RESTORE_SNAPSHOT", "false").lower() in ["true", "1", "yes"])

    return set_cosmovisor_dir(locals(), cosmovisor_dir)

def chain_name_from_hostname():
    hostname = os.environ.get("HOSTNAME", None)
    if hostname:
        chain_name = hostname.split('-')[0]
        return chain_name
    return None

def set_cosmovisor_dir(ctx, cosmovisor_dir):
    ctx["cosmovisor_dir"] = cosmovisor_dir
    ctx["cv_current_dir"] = os.path.join(cosmovisor_dir, "current")
    ctx["cv_genesis_dir"] = os.path.join(cosmovisor_dir, "genesis")
    ctx["cv_upgrades_dir"] = os.path.join(cosmovisor_dir, "upgrades")
    return ctx


def get_system_arch():
    """
    Identifies the system architecture.

    Returns:
        A string representing the system architecture in the format "<os_name>/<arch>".
    """
    logging.info("Identifying system architecture...")
    os_name = platform.system().lower()
    mach = platform.machine()
    logging.info(f"OS: {os_name}")
    logging.info(f"Machine: {mach}")
    if mach == "arm64" or mach == "aarch64":
        arch = "arm64"
    elif mach == "x86_64":
        arch = "amd64"
    else:
        arch = None
    if arch:
        return f"{os_name}/{arch}"
    else:
        return None


def get_arch_version(ctx, codebase, version):
    name = version.get("name", "")
    height = version.get("height", "")
    git_repo = codebase.get("git_repo", "")
    tag = version.get("tag", name)
    recommended_version = version.get("recommended_version", tag)
    libraries = version.get("libraries", {}).get(ctx["arch"], {})
    binaries = version.get("binaries", {})
    binary_url = binaries.get(ctx["arch"], binaries.get("docker/" + ctx["arch"], ""))
    return {
        "name": name,
        "height": height,
        "tag": tag,
        "git_repo": git_repo,
        "tag": tag,
        "recommended_version": recommended_version,
        "binary_url": binary_url,
        "libraries": libraries
    }


def create_cv_upgrade(ctx, version, linkCurrent=True):
    os.makedirs(ctx["cv_upgrades_dir"], exist_ok=True)
    daemon_name = ctx.get("daemon_name")
    upgrade_name = version.get("name", "")
    binary_url = version.get("binary_url", None)
    library_urls = version.get("libraries", {})

    upgrade_path = os.path.join(ctx["cv_upgrades_dir"], upgrade_name)
    binary_file = os.path.join(upgrade_path, "bin", daemon_name)

    logging.info(f"Found version {upgrade_name}, Checking for {upgrade_path}...")

    os.makedirs(upgrade_path, exist_ok=True)

    # add binary
    if binary_url:
        download_file(binary_url, binary_file)
        os.chmod(binary_file, 0o755)
    
    # add libraries
    os.makedirs(f"{upgrade_path}/lib", exist_ok=True)
    for key, library_url in library_urls.items():
        logging.info(f"Downloading library: {library_url}...")
        library_file = os.path.join(upgrade_path, "lib", key)
        download_file(library_url, library_file)
        os.chmod(library_file, 0o755)
        
    # link if binary exists
    if os.path.exists(binary_file):
        logging.info(f"Successfully added binary {binary_file}")
        create_upgrade_info(ctx, version, os.path.exists(ctx["cv_genesis_dir"] and True or False))
        if linkCurrent:
            link_cv_current(ctx, upgrade_path)
        if not os.path.exists(ctx["cv_genesis_dir"]):
            link_cv_genesis(ctx, upgrade_path)
    else:
        raise FileNotFoundError(f"Binary {binary_file} not found")


def create_upgrade_info(ctx, version, genesis=False):
    upgrade_name = version.get("name", "")
    binary_url = version.get("binary_url", None)
    upgrade_path = os.path.join(ctx["cv_upgrades_dir"], upgrade_name)
    time = version.get("time", "0001-01-01T00:00:00Z")
    height = version.get("height", genesis and 1 or 0)
    v_upgrade_info_json = f"{upgrade_path}/upgrade-info.json"
    if int(height or 0) >= 1 and not os.path.exists(v_upgrade_info_json):
        logging.info(f"Setting upgrade height for {upgrade_name} to {height}...")
        with open(v_upgrade_info_json, 'w') as f:
            json.dump({
                "name": upgrade_name, 
                "time": time, 
                "height": height, 
                "info": json.dumps({
                    "binaries": { ctx['arch']: binary_url }
                })
            }, f)
        os.chmod(v_upgrade_info_json, 0o644)


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


def download_file(url, file):
    path = os.path.dirname(file)
    name = os.path.basename(file)
    
    if not os.path.exists(file):
        print(f"Downloading {url} to {file}...")
        os.makedirs(path, exist_ok=True)
        if url.startswith("docker://"):
            download_and_extract_image(url, file)
            return

        with tempfile.TemporaryDirectory() as tmpdir:
            url_split = url.split('?')
            url_fname = os.path.basename(url_split[0])
            response = requests.get(url)
            response.raise_for_status()
            tmp_path = os.path.join(tmpdir, url_fname)
            logging.info(f"Downloading {url} to {tmp_path}...")
            with open(tmp_path, 'wb') as f:
                f.write(response.content)

            if url_fname.endswith(".tar.gz"):
                with tarfile.open(tmp_path ,mode='r:gz') as tar:
                    for member in tar.getmembers():
                        member_basename = os.path.basename(member.name)
                        if member.name.endswith(name) or member_basename.startswith(name):
                            logging.info(f"Extracting: {member.name} to {file}")
                            member.name = name
                            tar.extract(member, path=path)
            elif url_fname.endswith(".zip"):
                # this code does not work consistently
                with zipfile.ZipFile(tmp_path, 'r') as zip_ref:
                    for zip_info in zip_ref.infolist():
                        zip_name = zip_info.filename
                        if zip_name.endswith('/'):
                            continue
                        file_content = zip_ref.read(zip_name)
                        logging.info(f"Extract: {zip_name} to {file}")
                        with open(file, 'wb') as file_handle:
                            file_handle.write(file_content)
                            break
            else:
                shutil.copy(tmp_path, file)


    # with open(binary_file, 'r') as f_json:
    #     try:
    #         # should fail
    #         json_data = json.load(f_json)
    #         arch_binary_url = json_data.get('binaries', {}).get('ARCH', '')
    #         download_cv_version(arch_binary_url, binary_file)
    #     except Exception as e:
    #         f_json.close()


def download_and_extract_image(image_url: str, binary_file: str):
    daemon_name = os.path.basename(binary_file)
    destination = os.path.dirname(binary_file)
    file_to_extract = daemon_name
    image = os.path.basename(image_url)
    image_name = image.split('[:@]', 1)[0]


    # Check if the image exists on Docker Hub
    try:
        logging.info(f"Checking for {image_url}...")
        subprocess.run([
            "skopeo", "inspect",
            "--override-os=linux",
            "--override-arch=amd64",
            image_url,
        ], stdout=subprocess.PIPE, check=True)
    except subprocess.CalledProcessError:
        logging.info(f"The image {image_url} could not be found.")
        return

    # Create a temporary directory
    with tempfile.TemporaryDirectory() as tmpdir:
        # check if the image exists on Docker Hub
        try:
            logging.info(f"Downloading {image_url}...")
            # Run the subprocess command within the temporary directory
            subprocess.run([
                "skopeo", "inspect",
                "--override-os=linux",
                "--override-arch=amd64",
                image_url,
            ], stdout=subprocess.PIPE, check=True)
        except subprocess.CalledProcessError as e:
            logging.info(f"Failed to download {image_url}. Error: {e}")

        # Download the Docker image using skopeo
        tar_file_name = f"{tmpdir}/{image_name.replace(':', '_')}.tar"
        try:
            subprocess.run([
                "skopeo", "copy",
                "--override-os=linux",
                "--override-arch=amd64",
                image_url, 
                f"docker-archive:{tar_file_name}",
            ], stdout=subprocess.PIPE, check=True)
        except subprocess.CalledProcessError as e:
            logging.info(f"Failed to download the image {image}. Error: {e}")
            return
        
        print(os.listdir(tmpdir))

        # Extract blobs to a temporary directory
        blob_directory = f"{tmpdir}/blobs"
        try:
            logging.info(f"Extracting {tar_file_name} to {blob_directory}...")
            # Open the tar file in read mode
            with tarfile.open(tar_file_name, 'r') as tar:
                # Extract the specified file to the temporary directory
                tar.extractall(blob_directory)
        except Exception as e:
            logging.info(f"Failed to extract {tar_file_name}. Error: {e}")

        # iterate over the files in the blob directory
        for filename in os.listdir(blob_directory):
            if filename.endswith('.tar'):
                logging.info(f"Checking {filename} for {file_to_extract}...")
                # Construct the full file path
                blob_file_path = os.path.join(blob_directory, filename)
                # Open the tar file in read mode
                with tarfile.open(blob_file_path, 'r') as blobtar:
                    for member in blobtar.getmembers():
                        if member.isfile() and member.name.split('/')[-1] == file_to_extract:
                            member.name = os.path.basename(member.name)
                            logging.info(f"Found {file_to_extract} in {filename}...")
                            # If no KeyError is raised, extract the specific file
                            blobtar.extract(member, path=destination)
                            logging.info(f"Successfully extracted {file_to_extract} from {image}")
                            break


def unsafe_reset_all(ctx):
    data_dir = ctx.get('data_dir')
    # remove addrbook, imperfect logic, but should work for now
    config_dir = os.path.join(os.path.dirname(data_dir), 'config')
    addrbook_json = os.path.join(config_dir, 'addrbook.json')
    if os.path.exists(addrbook_json):
        os.remove(addrbook_json)
    
    # remove data_dir and recreate
    shutil.rmtree(data_dir, ignore_errors=True)
    os.makedirs(data_dir, exist_ok=True)
    with open(os.path.join(data_dir, 'priv_validator_state.json'), 'w') as file:
        file.write('{"height": "0", "round": 0, "step": 0}')