import os
import dns.resolver
import rpcstatus 
import tomlkit
import logging

def is_running_in_k8s():
    return "KUBERNETES_SERVICE_HOST" in os.environ

def get_service_peers(chain, domain):
    for hostport in get_service_rpc_addresses(chain, domain):
        try:
            status = rpcstatus.RpcStatus(f"http://{hostport}/status")
            ip = hostport.split(":")[0]
            id = status.node_info.id
            port = status.node_info.listen_addr.split(":")[2]
            yield f"{id}@{ip}:{port}"
        except Exception as e:
            logging.error(f"Could not retrieve status for {hostport}: {e}")
            pass


def get_service_rpc_status(chain, domain):
    for hostport in get_service_rpc_addresses(chain, domain):
        try:
            yield rpcstatus.RpcStatus(f"http://{hostport}/status")
        except Exception as e:
            logging.error(f"Could not retrieve status for {hostport}: {e}")
            pass


def get_service_rpc_addresses(chain, domain):
    for type in ["sync", "read", "write", "snap", "archive"]:
        for result in get_service_rpc_addresses_type(chain, domain, type):
            yield result


def get_service_rpc_addresses_type(chain, domain, type):
        try:
            serviceName = f'_rpc._tcp.discover-{chain}-{type}.{domain}'  # Replace with your service and protocol
            answers = dns.resolver.resolve(serviceName, 'SRV')
            for rdata in answers:
                ips = dns.resolver.resolve(rdata.target, 'A')
                for ip in (ip for ip in ips if ip is not None):
                    yield f"{ip}:{rdata.port}"
        except Exception as e:
            logging.warn(f"Could not retrieve dns for {serviceName}")
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

        print(f"Updated persistent peers: {updated_peers}")

        config["p2p"]["persistent_peers"] = updated_peers

        with open(config_file, "w") as file:
            file.write(tomlkit.dumps(config))

    except Exception as e:
        print(f"Error updating config file: {e}")