#!/bin/sh

# Define the file to store the previous block height
PREVIOUS_HEIGHT_FILE=/tmp/previous_height

# Get the current block height using curl and jq
current_height=$(curl -s localhost:26657/status | jq -re .result.sync_info.latest_block_height)

# Check if there was an error during the curl command
if [ $? -ne 0 ]; then
    echo "Error occurred while executing curl command."
    exit 1
fi

# Skip check if current block height is not available
if [ -z $current_height ]; then
    echo "Current block height is not available."
    exit 0
fi

# Create the previous height file if does not exist
if [ ! -f $PREVIOUS_HEIGHT_FILE ]; then
    echo 0 > $PREVIOUS_HEIGHT_FILE
fi

# Read the previous block height from the file
previous_height=$(cat $PREVIOUS_HEIGHT_FILE 2>/dev/null)

# Check if the current height is greater than the previous height
if [ $current_height -le $previous_height ]; then
    echo "Block height did not increase since the last check."
    exit 1
fi

# Save the current height as the previous height
echo $current_height > $PREVIOUS_HEIGHT_FILE

# Exit with success status
exit 0
