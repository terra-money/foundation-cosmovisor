import os
import sys
import select
import subprocess

# shell command to prune data directory
def main(data_dir):
    command = ["/usr/local/bin/cosmprund", "prune", data_dir]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    # Keep reading from the process's output pipes in real-time
    while True:
        # Use select to wait for output on either stdout or stderr
        reads = [process.stdout.fileno(), process.stderr.fileno()]
        ret = select.select(reads, [], [])

        for fd in ret[0]:
            if fd == process.stdout.fileno():
                read = process.stdout.readline()
                print(read.strip(), file=sys.stderr)
            if fd == process.stderr.fileno():
                read = process.stderr.readline()
                print(read.strip(), file=sys.stderr)

        # Break from the loop if the process is done
        if process.poll() is not None:
            break
        
if __name__ == '__main__':
    data_dir = os.environ.get('DATA_DIR')
    if data_dir:
        main(data_dir)