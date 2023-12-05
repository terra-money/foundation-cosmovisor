#! /usr/bin/env python3

import sys
import logging
import argparse
import xmlrpc.client


def is_running(process_name: str = "cosmovisor", supervisor_rpc_url: str = "http://127.0.0.1:9001/RPC2") -> None:
    """
    Check if a process is running using supervisord XML-RPC server.

    Args:
    process_name (str): The name of the process to check.

    Returns:
    bool: True if the process is running, False otherwise.
    """
    try:
        # Connect to the supervisord XML-RPC server
        server = xmlrpc.client.ServerProxy(supervisor_rpc_url)

        # Get process info
        process_info = server.supervisor.getProcessInfo(process_name)

        if process_info['statename'] == 'RUNNING':
            return True

    except xmlrpc.client.Fault as err:
        sys.stderr.write(f"Error: {err.faultString}\n")
    except ConnectionRefusedError:
        sys.stderr.write("Error: Connection refused.\n")
    except Exception as e:
        sys.stderr.write(f"Error: {e}\n")

    return False


def start_process(process_name: str = "cosmovisor", supervisor_rpc_url: str = "http://127.0.0.1:9001/RPC2") -> None:
    # Connect to the supervisord XML-RPC server
    server = xmlrpc.client.ServerProxy(supervisor_rpc_url)

    # Start the process
    try:
        server.supervisor.startProcess(process_name)
        sys.stderr.write(f"Started process: {process_name}",)
    except Exception as e:
        sys.stderr.write(f"Error starting process: {e}",)


def stop_process(process_name: str = "cosmovisor", supervisor_rpc_url: str = "http://127.0.0.1:9001/RPC2") -> None:
    """
    This function stops a process using the given process name and supervisor RPC URL.
    """
    try:
        # Connect to the supervisord XML-RPC server
        server = xmlrpc.client.ServerProxy(supervisor_rpc_url)

        # Stop the process
        server.supervisor.stopProcess(process_name)

        # Print success message
        logging.info(f"Stopped process: {process_name}")
    except Exception as e:
        # Print error message
        logging.error(f"Error stopping process: {e}")


def restart_process(process_name: str = "cosmovisor", supervisor_rpc_url: str = "http://127.0.0.1:9001/RPC2") -> None:
    """
    Restarts a process using the given supervisor RPC URL and process name.

    Args:
    - process_name (str): The name of the process to be restarted.
    - supervisor_rpc_url (str): The URL of the supervisor RPC server.

    Returns:
    - None
    """
    # Connect to the supervisord XML-RPC server
    server = xmlrpc.client.ServerProxy(supervisor_rpc_url)

    # Restart the plogging.infologging.infoerrorinfoprintlogging.infoerrors
    try:
        server.supervisor.stopProcess(process_name)
        server.supervisor.startProcess(process_name)
        sys.stderr.write(f"Restarted process: {process_name}")
    except Exception as e:
        sys.stderr.write(f"Error restarting process: {e}")

  
def main(args: argparse.Namespace) -> int:
    process_name = 'cosmovisor'
    action = args.action

    if action == 'start':
        start_process(process_name)
    elif action == 'stop':
        stop_process(process_name)
    elif action == 'restart':
        restart_process(process_name)
        
    return 0

        
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser(description='Load data from image snapshot.')
    parser.add_argument('action', type=str, choices=['start', 'stop', 'restart'], help='Action to perform (create or extract)')
    args = parser.parse_args()
    exit_code = main(args)
    exit(exit_code)