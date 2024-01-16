import os
import dns.resolver
import rpcstatus 
import logging

def is_running_in_k8s():
    return "KUBERNETES_SERVICE_HOST" in os.environ

# TODO: construct the dns SRV records to handle this automatically
def get_types_dns_names(chain, domain):
    types = ["", "-read", "-write", "-snap", "-archive"]
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
                logging.error(f"Could not retrieve status for {hostport}: {e}")
                pass


def get_service_rpc_status(chain, domain):
    for dns_name in get_types_dns_names(chain, domain):
        for hostport in get_service_rpc_addresses(dns_name):
            try:
                yield rpcstatus.RpcStatus(f"http://{hostport}/status")
            except Exception as e:
                logging.error(f"Could not retrieve status for {hostport}: {e}")
                pass


def get_service_rpc_addresses(dns_name):
    serviceName = f'_rpc._tcp.{dns_name}'  # Replace with your service and protocol
    answers = dns.resolver.resolve(serviceName, 'SRV')
    for rdata in answers:
        ips = dns.resolver.resolve(rdata.target, 'A')
        for ip in (ip for ip in ips if ip is not None):
            yield f"{ip}:{rdata.port}"

