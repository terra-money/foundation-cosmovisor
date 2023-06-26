#!/bin/sh

HOME_PATH=${HOME_PATH:="/app"}
TRANSACTION_FEE=${TRANSACTION_FEE:="3000uluna"}
CHECK_INTERVAL=${CHECK_INTERVAL:=300}
TERRA_BINARY=${TERRA_BINARY:="$HOME_PATH/cosmovisor/current/bin/terrad"}
ACCOUNT_NAME=${ACCOUNT_NAME:=$(cat "$HOME_PATH"/config/config.toml | grep moniker | awk -F'"' '{print $2}')}

if [ -z "$KEYRING_PASSPHRASE" ]; then
    echo "$(date): Error: KEYRING_PASSPHRASE variable is empty."
    exit 1
elif [ -z "$ACCOUNT_NAME" ]; then
    echo "$(date): Error: ACCOUNT_NAME variable is empty."
    exit 1
fi

send_transaction() {
    echo "$(date): Sending unjail transaction..."
    echo "$KEYRING_PASSPHRASE" | $TERRA_BINARY tx slashing unjail \
        --from $ACCOUNT_NAME \
        --fees $TRANSACTION_FEE \
        --yes \
        --home $HOME_PATH | tail -n1
}

unjail_validator() {
    while true; do
        catching_up=$("$TERRA_BINARY" status | jq -r .SyncInfo.catching_up)
        if [ $? -ne 0 ]; then
            echo "$(date): Error: Node status is not available."
            break
        elif [ "$catching_up" == "false" ]; then
            send_transaction
            break
        else
            echo "$(date): Waiting 60s for validator to catch up..."
            sleep 60
        fi
    done
}

while true; do
    voting_power=$("$TERRA_BINARY" status | jq -r .ValidatorInfo.VotingPower)
    if [ $? -ne 0 ]; then
        echo "$(date): Error: Node status is not available."
    elif [ $voting_power -gt 0 ]; then
        echo "$(date): Validator is active. Voting power: $voting_power"
    else
        echo "$(date): Validator is jailed. Voting power: $voting_power"
        unjail_validator
    fi

    echo "$(date): Sleeping for $CHECK_INTERVAL seconds..."
    sleep $CHECK_INTERVAL
done
