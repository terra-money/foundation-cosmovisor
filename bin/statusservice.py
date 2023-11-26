#! /usr/bin/env python3
import requests
import json
import os
import sys
import cvcontrol
import getstatus

# Path to save the file
home_dir = os.path.expanduser('~')
default_data_dir = os.path.join(home_dir, 'data')
data_dir = os.environ.get('DATA_DIR', default_data_dir)
file_path = os.path.join(data_dir, 'status.json')

# Ensure the 'data' directory exists
os.makedirs(data_dir, exist_ok=True)

def write_stdout(s):
    sys.stdout.write(s)
    sys.stdout.flush()

def write_stderr(s):
    sys.stderr.write(s)
    sys.stderr.flush()

def write_status(): 
    # Perform the GET request
    status = getstatus.get_status('http://localhost:26657/status')
    
    # Write the JSON data to the file
    if status is not None:
        with open(file_path, 'w') as file:
            json.dump(status, file, indent=4)

        write_stderr(f"Data written to {file_path}")

def main():
    while 1:
        # transition from ACKNOWLEDGED to READY
        write_stdout('READY\n')

        # read header line and print it to stderr
        line = sys.stdin.readline()
        # write_stderr(line)

        # read event payload and print it to stderr
        # headers = dict([ x.split(':') for x in line.split() ])
        # data = sys.stdin.read(int(headers['len']))
        # write_stderr(data)

        # write status file
        if cvcontrol.is_running("cosmovisor"):
            write_status()

        # transition from READY to ACKNOWLEDGED (ignore fail/best effort)
        write_stdout('RESULT 2\nOK')

if __name__ == '__main__':
    main()