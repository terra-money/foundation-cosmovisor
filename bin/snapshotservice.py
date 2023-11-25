#! /usr/bin/env python3

import os
import sys
import getstatus
import snapshot
from datetime import datetime, time

# Define time range
start = time(5, 0)  # 05:00 UTC
stop = time(6, 0)    # 06:00 UTC

# write to stdout and flush
def write_stdout(s):
    sys.stdout.write(s)
    sys.stdout.flush()

# write to stderr and flush
def write_stderr(s):
    sys.stderr.write(s)
    sys.stderr.flush()


def is_ready():
    # Check if the current time is between midnight and 1 AM UTC
    if not (start <= datetime.utcnow().time() < stop):
        write_stderr(f"Current time is not between {start} and {stop} UTC.")
        return False
    if not getstatus.is_catching_up():
        write_stderr(f"Node is not catching up.")
        return False
    return True

def main(data_dir, snapshots_dir, cosmprund_enabled):
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

        if is_ready():
            snapshot.create_snapshot(data_dir, snapshots_dir, cosmprund_enabled)

        # transition from READY to ACKNOWLEDGED (ignore fail/best effort)
        write_stdout('RESULT 2\nOK')

if __name__ == '__main__':
    user_home = os.path.expanduser('~')
    chain_home = os.environ.get('CHAIN_HOME', user_home)
    default_data_dir = os.path.join(chain_home, 'data')
    data_dir = os.environ.get('DATA_DIR', default_data_dir)
    default_snapshots_dir = os.path.join(os.path.dirname(data_dir), 'shared', 'snapshots')
    snapshots_dir = os.environ.get('SNAPSHOTS_DIR', default_snapshots_dir)
    cosmprund_enabled = os.getenv('COSMPRUND_ENABLED', 'false').lower() in ['true', '1', 'yes']
    main(data_dir, snapshots_dir, cosmprund_enabled)