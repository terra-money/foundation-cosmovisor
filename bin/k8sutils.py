import os
import dns.resolver
import rpcstatus 
import tomlkit
import logging

def is_running_in_k8s():
    return "KUBERNETES_SERVICE_HOST" in os.environ

# TODO: construct the dns SRV records to handle this automatically
def get_types_dns_names(chain, domain):
    types = ["-sync", "-read", "-write", "-snap", "-archive"]
    for type in types:
        yield f"discover-{chain}{type}.{domain}"  # Replace with your domain


def get_service_peers(chain, domain):
    for dns_name in get_types_dns_names(chain, domain):
        for hostport in get_service_rpc_addresses(dns_name):
            try:
                status = rpcstatus.RpcStatus(f"http://{hostport}/status")
                ip = hostport.split(":")[0]
                id = status.node_info.id
                port = status.node_info.listen_addr.split(":")[2]
                yield f"{id}@{ip}:{port}"
            except Exception as e:
                logging.debug(f"Could not retrieve status for {hostport}: {e}")
                pass


def get_service_rpc_status(chain, domain):
    for dns_name in get_types_dns_names(chain, domain):
        for hostport in get_service_rpc_addresses(dns_name):
            try:
                yield rpcstatus.RpcStatus(f"http://{hostport}/status")
            except Exception as e:
                logging.debug(f"Could not retrieve status for {hostport}: {e}")
                pass


def get_service_rpc_addresses(dns_name):
    serviceName = f'_rpc._tcp.{dns_name}'  # Replace with your service and protocol
    try:
        answers = dns.resolver.resolve(serviceName, 'SRV')
        for rdata in answers:
            ips = dns.resolver.resolve(rdata.target, 'A')
            for ip in (ip for ip in ips if ip is not None):
                yield f"{ip}:{rdata.port}"
    except Exception as e:
        logging.warn(e)
        pass

# Function to add node IDs as persistent peers in config.toml
def add_persistent_peers(ctx):
    try:
        config_file = ctx["config_toml"]
        peers = get_service_peers(ctx["chain_name"], ctx["domain"])
        with open(config_file, "r") as file:
            config = tomlkit.parse(file.read())

        existing_peers = config.get("p2p", {}).get("persistent_peers", "")
        existing_peers_set = set(existing_peers.split(',')) if existing_peers else set()

        # Convert the nodes to a set to remove duplicates and then merge with existing
        peers_set = set(peers)
        updated_peers_set = existing_peers_set.union(peers_set)

        # Convert back to a comma-separated string
        updated_peers = ",".join(updated_peers_set)

        logging.info(f"Updated persistent peers: {updated_peers}")

        config["p2p"]["persistent_peers"] = updated_peers

        with open(config_file, "w") as file:
            file.write(tomlkit.dumps(config))

    except Exception as e:
        logging.error(f"Error updating config file: {e}")