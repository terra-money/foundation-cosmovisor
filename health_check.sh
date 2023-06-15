#!/bin/sh

PREVIOUS_HEIGHT_FILE=${PREVIOUS_HEIGHT_FILE:="/tmp/previous_height"}
TENDERMINT_ENDPOINT=${TENDERMINT_ENDPOINT:="localhost:26657"}

CURL_MAXIMUM_REQUESTS=${CURL_MAXIMUM_REQUESTS:="5"}
CURL_INTERVAL=${CURL_INTERVAL:="1"}
CHECK_MAXIMUM_RETRIES=${CHECK_MAXIMUM_RETRIES:="5"}
CHECK_INTERVAL=${CHECK_INTERVAL:="1"}

get_current_height() {
    local requests=1

    while [ $requests -le $CURL_MAXIMUM_REQUESTS ]; do
        current_height=$(curl -s $TENDERMINT_ENDPOINT/status | jq -re .result.sync_info.latest_block_height)

        if [ $? -ne 0 ]; then
            echo "Error occurred while executing curl command. Retrying."
        else
            break
        fi

        requests=$((requests + 1))
        sleep $CURL_INTERVAL
    done

    if [ $requests -gt $CURL_MAXIMUM_REQUESTS ]; then
        echo "Failed to retrieve current block height after $CURL_MAXIMUM_REQUESTS attempts."
        exit 1
    fi
}

get_previous_height() {
    if [ -f $PREVIOUS_HEIGHT_FILE ]; then
        previous_height=$(cat $PREVIOUS_HEIGHT_FILE)
        if [ $? -ne 0 ]; then
            echo "Error occurred while reading previous height file."
            exit 1
        fi
    else
        previous_height=0
    fi
}

save_previous_height() {
    echo $current_height > $PREVIOUS_HEIGHT_FILE
    if [ $? -ne 0 ]; then
        echo "Error occurred while saving previous height file."
        exit 1
    fi
}

health_check() {
    get_current_height
    if [ -z $current_height ]; then
        echo "Current block height is not available."
        if [ -f $PREVIOUS_HEIGHT_FILE ]; then
            exit 1
        else
            exit 0
        fi
    fi

    get_previous_height
    if [ $current_height -le $previous_height ]; then
        echo "Block height did not increase since the last check. Retrying."
    else
        save_previous_height
        echo "Block height increased since last check."
        exit 0
    fi
}

retries=1

while [ $retries -le $CHECK_MAXIMUM_RETRIES ]; do
    health_check
    retries=$((retries + 1))
    sleep $CHECK_INTERVAL
done

if [ $retries -gt $CHECK_MAXIMUM_RETRIES ]; then
    echo "Block height did not increase after $CHECK_MAXIMUM_RETRIES attempts."
    exit 1
fi
