#!/bin/bash

set -euo pipefail

DAEMON_HOME=${DAEMON_HOME:="$(pwd)"}
CHAIN_HOME=${CHAIN_HOME:=$DAEMON_HOME}
CHAIN_JSON="${DAEMON_HOME}/chain.json"
UPGRADES_YML="${DAEMON_HOME}/upgrades.yml"

# Chain information
get_chain_json(){
    if [ -z "${CHAIN_JSON_URL:=""}" ] && [ -n "${CHAIN_NAME:=""}" ]; then
        CHAIN_JSON_URL=https://raw.githubusercontent.com/cosmos/chain-registry/master/${CHAIN_NAME}/chain.json
    fi
    logger "Retrieving chain information from ${CHAIN_JSON_URL}..."
    # always download newest version of chain.json
    curl -sSL "${CHAIN_JSON_URL}" -o "${CHAIN_JSON}"
}

create_upgrades_yaml(){
    if [ ! -f "${CHAIN_JSON}" ]; then
        get_chain_json
    fi
    yq '{daemon_name: .daemon_name, libraries: [], versions: .codebase.versions}' "${CHAIN_JSON}" > ${UPGRADES_YML}
}

parse_chain_info(){
    logger "Parsing chain information..."
    export DAEMON_NAME=${DAEMON_NAME:="$(jq -r ".daemon_name" ${CHAIN_JSON})"}
    export CHAIN_ID=${CHAIN_ID:="$(jq -r ".chain_id" ${CHAIN_JSON})"}

    # Codebase Versions
    GENESIS_VERSION=${GENESIS_VERSION:="$(jq -r ".codebase.genesis.name" ${CHAIN_JSON})"}
    RECOMMENDED_VERSION=${RECOMMENDED_VERSION:="$(jq -r ".codebase.recommended_version" ${CHAIN_JSON})"}
    # Prefer recommended version over upgrade.json
    PREFER_RECOMMENDED_VERSION=${PREFER_RECOMMENDED_VERSION:="false"}

    # app.toml
    CONTRACT_MEMORY_CACHE_SIZE=${CONTRACT_MEMORY_CACHE_SIZE:=8192}
    ENABLE_API=${ENABLE_API:=true}
    ENABLE_SWAGGER=${ENABLE_SWAGGER:=true}
    KEEP_SNAPSHOTS=${KEEP_SNAPSHOTS:=10}
    MONIKER=${MONIKER:="moniker"}
    MINIMUM_GAS_PRICES=${MINIMUM_GAS_PRICES:="$(jq -r '.fees.fee_tokens[] | [ .average_gas_price, .denom ] | join("")' ${CHAIN_JSON} | paste -sd, -)"}
    PRUNING_INTERVAL=${PRUNING_INTERVAL:=2000}
    PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:=5}
    PRUNING_KEEP_EVERY=${PRUNING_KEEP_EVERY:=2000}
    MIN_RETAIN_BLOCKS=${MIN_RETAIN_BLOCKS:=2000}
    # choosing nothing as the default pruning strategy
    # to avoid accidentally pruning data on an archival node
    PRUNING_STRATEGY=${PRUNING_STRATEGY:="nothing"}
    SNAPSHOT_INTERVAL=${SNAPSHOT_INTERVAL:=${MIN_RETAIN_BLOCKS}}
    RPC_MAX_BODY_BYTES=${RPC_MAX_BODY_BYTES:=1500000}

    # config.toml
    ADDR_BOOK_STRICT=${ADDR_BOOK_STRICT:=false}
    ADDR_BOOK_URL=${ADDR_BOOK_URL:=}
    ALLOW_DUPLICATE_IP=${ALLOW_DUPLICATE_IP:=true}
    BOOTSTRAP_PEERS=${BOOTSTRAP_PEERS:=}
    CHUNK_FETCHERS=${CHUNK_FETCHERS:=30}
    DB_BACKEND=${DB_BACKEND:=goleveldb}
    DIAL_TIMEOUT=${DIAL_TIMEOUT:=5s}
    LOG_FORMAT=${LOG_FORMAT:=json}
    FAST_SYNC=${FAST_SYNC:="true"}
    TIMEOUT_BROADCAST_TX_COMMIT=${TIMEOUT_BROADCAST_TX_COMMIT:=45s}
    UNSAFE_SKIP_BACKUP=${UNSAFE_SKIP_BACKUP=true}
    MAX_BODY_BYTES=${MAX_BODY_BYTES:=2000000}
    GENESIS_URL=${GENESIS_URL:="$(jq -r ".codebase.genesis.genesis_url" ${CHAIN_JSON})"}
    IS_SEED_NODE=${IS_SEED_NODE:="false"}
    IS_SENTRY=${IS_SENTRY:="false"}
    MAX_PAYLOAD=${MAX_PAYLOAD:=}
    METRIC_NAMESPACE=${METRIC_NAMESPACE:="tendermint"}
    NODE_KEY=${NODE_KEY:=}
    NODE_MODE=${NODE_MODE:=}
    PERSISTENT_PEERS=${PERSISTENT_PEERS:="$(jq -r '.peers.persistent_peers[] | [.id, .address] | join("@")' ${CHAIN_JSON} | paste -sd, -)"}
    SEEDS=${SEEDS:="$(jq -r '.peers.seeds[] | [.id, .address] | join("@")' ${CHAIN_JSON} | paste -sd, -)"}
    SENTRIED_VALIDATOR=${SENTRIED_VALIDATOR:="false"}
    PRIVATE_VALIDATOR_KEY=${PRIVATE_VALIDATOR_KEY:=}
    PRIVATE_PEER_IDS=${PRIVATE_PEER_IDS:=}
    PUBLIC_ADDRESS=${PUBLIC_ADDRESS:=}
    UNCONDITIONAL_PEER_IDS=${UNCONDITIONAL_PEER_IDS:=}
    USE_HORCRUX=${USE_HORCRUX:="false"}
    MAX_NUM_INBOUND_PEERS=${MAX_NUM_INBOUND_PEERS:=20}
    MAX_NUM_OUTBOUND_PEERS=${MAX_NUM_OUTBOUND_PEERS:=40}
    TIMEOUT_COMMIT=${TIMEOUT_COMMIT:=}

    # State sync
    WASM_URL=${WASM_URL:=}
    TRUST_LOOKBACK=${TRUST_LOOKBACK:=2000}
    RESET_ON_START=${RESET_ON_START:="false"}
    STATE_SYNC_RPC=${STATE_SYNC_RPC:=}
    STATE_SYNC_WITNESSES=${STATE_SYNC_WITNESSES:="${STATE_SYNC_RPC}"}
    STATE_SYNC_ENABLED=${STATE_SYNC_ENABLED:="$([ -n "${STATE_SYNC_WITNESSES}" ] && echo "true" || echo "false")"}
    SYNC_BLOCK_HEIGHT=${SYNC_BLOCK_HEIGHT:="${FORCE_SNAPSHOT_HEIGHT:="$(get_sync_block_height)"}"}
    SYNC_BLOCK_HASH=${SYNC_BLOCK_HASH:="$(get_sync_block_hash)"}
}

# check to see if this file is being run or sourced from another script
_is_sourced() {
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

_main(){
    get_chain_json
    parse_chain_info
}

# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
	_main "$@"
fi
