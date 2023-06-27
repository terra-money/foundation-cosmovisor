#!/bin/sh

DAEMON_HOME=${DAEMON_HOME:="/app"}
TRANSACTION_FEE=${TRANSACTION_FEE:="3000uluna"}
CHECK_INTERVAL=${CHECK_INTERVAL:=300}
TERRA_BINARY=${TERRA_BINARY:="$DAEMON_HOME/cosmovisor/current/bin/terrad"}
ACCOUNT_NAME=${ACCOUNT_NAME:=$(cat "$DAEMON_HOME"/config/config.toml | grep moniker | awk -F'"' '{print $2}')}

if [ -z "$KEYRING_PASSPHRASE" ]; then
    echo "$(date): Error: KEYRING_PASSPHRASE variable is empty."
    exit 1
elif [ -z "$ACCOUNT_NAME" ]; then
    echo "$(date): Error: ACCOUNT_NAME variable is empty."
    exit 1
fi

while true; do
    status=$("$TERRA_BINARY" status --home $DAEMON_HOME 2> /dev/null)
    if [ $? -ne 0 ]; then
        echo "$(date): Error: Node status is not available."
    fi

    voting_power=$(echo "$status" | jq -r .ValidatorInfo.VotingPower)
    catching_up=$(echo "$status" | jq -r .SyncInfo.catching_up)

    if [ -n "$voting_power" ]; then
        if [ $voting_power -gt 0 ]; then
            echo "$(date): Validator is active. Voting power: $voting_power"
        elif [ "$catching_up" = "false" ]; then
            echo "$(date): Validator is jailed. Voting power: $voting_power"
            echo "$(date): Sending unjail transaction..."

            echo "$KEYRING_PASSPHRASE" | $TERRA_BINARY tx slashing unjail \
                --from $ACCOUNT_NAME \
                --fees $TRANSACTION_FEE \
                --yes \
                --home $DAEMON_HOME | tail -n1
        else
            echo "$(date): Validator is jailed. Voting power: $voting_power"
            echo "$(date): Waiting for validator to catch up..."
        fi
    fi

    echo "$(date): Sleeping for $CHECK_INTERVAL seconds..."
    sleep $CHECK_INTERVAL
done
