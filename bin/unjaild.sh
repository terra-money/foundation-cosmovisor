#!/bin/sh

if [ -n "${DEBUG:=}" ]; then
    set -x
fi

CHAIN_HOME=${CHAIN_HOME:$(pwd)}
TRANSACTION_FEE=${TRANSACTION_FEE:="3000uluna"}
CHECK_INTERVAL=${CHECK_INTERVAL:=300}
ACCOUNT_NAME=${ACCOUNT_NAME:=$(awk -F'"' '/^moniker/{print $2}' "${CHAIN_HOME}/config/config.toml")}

if [ -z "${KEYRING_PASSPHRASE}" ]; then
    echo "$(date): Error: KEYRING_PASSPHRASE variable is empty."
    exit 1
elif [ -z "${ACCOUNT_NAME}" ]; then
    echo "$(date): Error: ACCOUNT_NAME variable is empty."
    exit 1
fi

while true; do
    status=$(cosmovisor run status --home ${CHAIN_HOME} 2> /dev/null)
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

            echo "$KEYRING_PASSPHRASE" | cosmovisor run tx slashing unjail \
                --from $ACCOUNT_NAME \
                --fees $TRANSACTION_FEE \
                --yes \
                --home $CHAIN_HOME | tail -n1
        else
            echo "$(date): Validator is jailed. Voting power: $voting_power"
            echo "$(date): Waiting for validator to catch up..."
        fi
    fi

    echo "$(date): Sleeping for $CHECK_INTERVAL seconds..."
    sleep $CHECK_INTERVAL
done
