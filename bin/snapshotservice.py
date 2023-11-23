#! /usr/bin/env python3

import sys
import getstatus
import snapshot
from time import sleep
from datetime import datetime, time

# Define time range
midnight = time(0, 0)  # 00:00 UTC
one_am = time(1, 0)    # 01:00 UTC

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
    if not (midnight <= datetime.utcnow().time() < one_am):
        write_stderr(f"Current time is not between {midnight} and {one_am} UTC.")
        return False
    if not getstatus.is_catching_up():
        write_stderr(f"Node is not catching up.")
        return False
    return True

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

        if is_ready():
            snapshot.main()

        # transition from READY to ACKNOWLEDGED (ignore fail/best effort)
        write_stdout('RESULT 2\nOK')

if __name__ == '__main__':
    main()