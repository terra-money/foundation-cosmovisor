#!/usr/bin/env python3

import os
import tarfile
import zipfile
import json
import requests
import shutil
import logging
import subprocess
import tempfile

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
    chain_network = os.environ.get('CHAIN_NETWORK', 'mainnet')
    daemon_name = os.environ.get("DAEMON_NAME", f"{chain_name}d")
    chain_json_url = os.environ.get('CHAIN_JSON_URL', None)

    chain_json_path = os.path.join('/etc/default', 'chain.json')
    upgrades_yaml_path = os.path.join('/etc/default', 'upgrades.yml')
    upgrades_json_path = os.path.join('/etc/default', 'upgrades.json')

    opt_cosmovisor_dir = os.path.join('/opt', "cosmovisor")
    cosmovisor_dir = os.path.join(daemon_home, "cosmovisor")
    cv_current_dir = os.path.join(cosmovisor_dir, "current")
    cv_genesis_dir = os.path.join(cosmovisor_dir, "genesis")
    cv_upgrades_dir = os.path.join(cosmovisor_dir, "upgrades")

    config_dir = os.path.join(chain_home, "config")
    data_dir = os.path.join(chain_home, "data")
    upgrade_info_json = os.path.join(data_dir, "upgrade-info.json")

    return {
        "arch": arch,
        "debug": debug,
        "daemon_home": daemon_home,
        "chain_name": chain_name,
        "chain_network": chain_network,
        "daemon_name": daemon_name,
        "chain_json_url": chain_json_url,

        "chain_json_path": chain_json_path,
        "upgrades_json_path": upgrades_json_path,
        "upgrades_yaml_path": upgrades_yaml_path,
        "upgrade_info_json": upgrade_info_json,

        "opt_cosmovisor_dir": opt_cosmovisor_dir,
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
    binary_url = binaries.get(ctx["arch"], binaries.get("docker/" + ctx["arch"], ""))
    return {
        "name": name,
        "height": height,
        "tag": tag,
        "git_repo": git_repo,
        "tag": tag,
        "recommended_version": recommended_version,
        "binary_url": binary_url,
    }


def check_cv_path(ctx):
    source_path = ctx['opt_cosmovisor_dir']
    destination_path = ctx['cosmovisor_dir']

    # nothing to do if the source does not exist
    if not os.path.exists(source_path):
        return

    source_dev = os.stat(source_path).st_dev

    # dir is link but not pointing to the expected target
    if os.path.islink(destination_path):
        actual_target = os.readlink(destination_path)
        logging.info(f"{actual_target}")
        if actual_target != source_path:
            os.path.unlink(destination_path)

    # Check if the link_path exists
    if not os.path.exists(destination_path):
        logging.info(f"Error: Path '{destination_path}' does not exist.")
        if source_dev != os.stat(ctx['daemon_home']).st_dev:
            logging.info(f"Copying '{source_path}' -> '{destination_path}'...")
            shutil.copytree(source_path, destination_path)
        else:
            logging.info(f"Creating symbolic link '{source_path}' -> '{destination_path}'...")
            os.symlink(destination_path, source_path)

    # dir is not a link but is not empty
    if source_dev != os.stat(destination_path).st_dev:
        logging.info(f"Copying '{source_path}' -> '{destination_path}'...")
        for subpath in os.listdir(f"{source_path}/upgrades"):
            if os.path.exists(f"{destination_path}/upgrades/{subpath}"):
                shutil.rmtree(f"{destination_path}/upgrades/{subpath}")
            if not os.path.exists(f"{destination_path}/upgrades/{subpath}"):
                os.makedirs(f"{destination_path}/upgrades/{subpath}")
                shutil.copytree(f"{source_path}/upgrades/{subpath}", f"{destination_path}/upgrades/{subpath}", dirs_exist_ok=True)

    return


def create_cv_upgrade(ctx, version, linkCurrent=True):
    os.makedirs(ctx["cv_upgrades_dir"], exist_ok=True)
    daemon_name = ctx.get("daemon_name")
    upgrade_name = version.get("name", "")
    binary_url = version.get("binary_url", {})
    tag = version.get("tag", "")
    name = ctx.get("chain_name", "")

    upgrade_path = os.path.join(ctx["cv_upgrades_dir"], upgrade_name)
    binary_file = os.path.join(upgrade_path, "bin", daemon_name)

    logging.info(f"Found version {upgrade_name}, Checking for {upgrade_path}...")

    os.makedirs(upgrade_path, exist_ok=True)
    os.makedirs(f"{upgrade_path}/lib", exist_ok=True)
    if binary_url:
        download_cv_version(binary_url, binary_file)

    if os.path.exists(binary_file):
        logging.info(f"Successfully added binary {binary_file}")
        if linkCurrent:
            link_cv_current(ctx, upgrade_path)
        if not os.path.exists(ctx["cv_genesis_dir"]):
            link_cv_genesis(ctx, upgrade_path)
    else:
        raise FileNotFoundError(f"Binary {binary_file} not found")


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
    daemon_name = os.path.basename(binary_file)

    if not os.path.exists(binary_file):
        print(f"Downloading {binary_url} to {binary_file}...")
        os.makedirs(binary_path, exist_ok=True)

        with tempfile.TemporaryDirectory() as tmpdir:
            if binary_url.startswith("docker://"):
                download_and_extract_image(binary_url, binary_file)
            else:
                binary_url_split = binary_url.split('?')
                binary_url_fname = os.path.basename(binary_url_split[0])
                response = requests.get(binary_url)
                response.raise_for_status()
                tmp_path = os.path.join(tmpdir, binary_url_fname)
                logging.error(f"Downloading {binary_url} to {tmp_path}...")
                with open(tmp_path, 'wb') as f:
                    f.write(response.content)

                if binary_url_fname.endswith(".tar.gz"):
                    with tarfile.open(tmp_path ,mode='r:gz') as tar:
                        for member in tar.getmembers():
                            if member.name.endswith(daemon_name):
                                member.name = daemon_name
                                tar.extract(member, path=binary_path)
                                subprocess.run(["ls", "-al", binary_path])
                elif binary_url_fname.endswith(".zip"):
                    # this code does not work consistently
                    with zipfile.ZipFile(tmp_path, 'r') as zip_ref:
                        for zip_info in zip_ref.infolist():
                            zip_name = zip_info.filename
                            if zip_name.endswith('/'):
                                continue
                            file_content = zip_ref.read(zip_name)
                            logging.info(f"Extract: {zip_name} to {binary_file}")
                            with open(binary_file, 'wb') as file_handle:
                                file_handle.write(file_content)
                                break
                else:
                    shutil.copy(tmp_path, binary_file)

        os.chmod(binary_file, 0o755)

    # with open(binary_file, 'r') as f_json:
    #     try:
    #         # should fail
    #         json_data = json.load(f_json)
    #         arch_binary_url = json_data.get('binaries', {}).get('ARCH', '')
    #         download_cv_version(arch_binary_url, binary_file)
    #     except:
    #         f_json.close()


def get_upgrade_info_version(ctx):
    logging.info(f"Downloading binary identified in {ctx['upgrade_info_json']}...")

    with open(ctx['upgrade_info_json'], 'r') as f:
        data = json.load(f)
        name = data.get('name', '')
        logging.info(f"upgrade name is {name}")
        info = data.get('info', '').rstrip(',')
        info = info.replace("'", '"')
        logging.info(f"upgrade info is {info}")
        if isinstance(info, str):
            if 'binaries' in info:
                info = json.loads(info)
                binaries = info.get('binaries', {})
                binary_url = binaries.get(ctx["arch"], None)
                return {"name": name, "binary_url": binary_url}
            elif 'http:' in info:
                return {"name": name, "binary_url": info}
    return None


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
