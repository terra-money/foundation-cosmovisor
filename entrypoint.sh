#!/bin/sh

set -eu

if [ -n "${DEBUG:=}" ]; then 
    set -x
fi

DAEMON_HOME=${DAEMON_HOME:="$(pwd)"}
CHAIN_JSON="${DAEMON_HOME}/chain.json"

# data directory
DATA_DIR="${DAEMON_HOME}/data"
UPGRADE_JSON="${DATA_DIR}/upgrade-info.json"

# Config directory
CONFIG_DIR="${DAEMON_HOME}/config"
ADDR_BOOK_FILE="${CONFIG_DIR}/addrbook.json"
APP_TOML="${CONFIG_DIR}/app.toml"
CLIENT_TOML="${CONFIG_DIR}/client.toml"
CONFIG_TOML="${CONFIG_DIR}/config.toml"
GENESIS_FILE="${CONFIG_DIR}/genesis.json"
NODE_KEY_FILE=${CONFIG_DIR}/node_key.json
PV_KEY_FILE=${CONFIG_DIR}/priv_validator_key.json

# Cosmovisor directory
COSMOVISOR_DIR="${DAEMON_HOME}/cosmovisor"
CV_CURRENT_DIR="${COSMOVISOR_DIR}/current"
CV_GENESIS_DIR="${COSMOVISOR_DIR}/genesis"
CV_UPGRADES_DIR="${COSMOVISOR_DIR}/upgrades"

main(){
    get_system_info
    get_chain_json
    parse_chain_info
    download_binaries
    initialize_node
    download_genesis
    download_addrbook
    set_node_key
    set_private_validator_key
    modify_client_toml
    modify_config_toml
    modify_app_toml
}

logger(){
    echo "$*"
}

# System information
get_system_info(){
    logger "Identifying system architecture..."
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    MACH=$(uname -m)
    if [ "${MACH}" = "x86_64" ]; then
        ARCH="${OS}/amd64"
    elif [ "${MACH}" = "aarch64" ]; then
        ARCH="${OS}/arm64"
    fi
}

# Chain information
get_chain_json(){
    logger "Retrieving chain information from ${CHAIN_JSON_URL}"
    if [ ! -f "${CHAIN_JSON}" ]; then
        wget "${CHAIN_JSON_URL}" -O "${CHAIN_JSON}"
    fi
}

parse_chain_info(){
    logger "Parsing chain information..."
    export DAEMON_NAME=${DAEMON_NAME:="$(jq -r ".daemon_name" ${CHAIN_JSON})"}
    export CHAIN_ID=${CHAIN_ID:="$(jq -r ".chain_id" ${CHAIN_JSON})"}

    MONIKER=${MONIKER:=moniker}
    PRUNING_STRATEGY=${PRUNING_STRATEGY:=nothing}
    PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:=0}
    PRUNING_INTERVAL=${PRUNING_INTERVAL:=0}
    PRUNING_KEEP_EVERY=${PRUNING_KEEP_EVERY:=0}
    SNAPSHOT_INTERVAL=${SNAPSHOT_INTERVAL:=0}
    KEEP_SNAPSHOTS=${KEEP_SNAPSHOTS:=5}
    TRUST_LOOKBACK=${TRUST_LOOKBACK:=2000}
    DB_BACKEND=${DB_BACKEND:=goleveldb}
    CONTRACT_MEMORY_CACHE_SIZE=${CONTRACT_MEMORY_CACHE_SIZE:=8192}

    LOG_FORMAT=${LOG_FORMAT:=json}
    TIMEOUT_BROADCAST_TX_COMMIT=${TIMEOUT_BROADCAST_TX_COMMIT:=45s}
    MAX_BODY_BYTES=${MAX_BODY_BYTES:=2000000}
    ADDR_BOOK_STRICT=${ADDR_BOOK_STRICT:=false}
    ALLLOW_DUPLICATE_IP=${ALLLOW_DUPLICATE_IP:=true}
    DIAL_TIMEOUT=${DIAL_TIMEOUT:=5s}
    CHUNK_FETCHERS=${CHUNK_FETCHERS:=30}
    ENABLE_API=${ENABLE_API:=true}
    ENABLE_SWAGGER=${ENABLE_SWAGGER:=true}
    UNSAFE_SKIP_BACKUP=${UNSAFE_SKIP_BACKUP=true}

    GENESIS_VERSION=${GENESIS_VERSION:="$(jq -r ".codebase.genesis.name" ${CHAIN_JSON})"}
    GENESIS_URL=${GENESIS_URL:="$(jq -r ".codebase.genesis.genesis_url" ${CHAIN_JSON})"}
    SEEDS=${SEEDS:="$(jq -r '.peers.seeds[] | [.id, .address] | join("@")' ${CHAIN_JSON} | paste -sd, -)"}
    PERSISTENT_PEERS=${PERSISTENT_PEERS:="$(jq -r '.peers.persistent_peers[] | [.id, .address] | join("@")' ${CHAIN_JSON} | paste -sd, -)"}
    MINIMUM_GAS_PRICES=${MINIMUM_GAS_PRICES:="$(jq -r '.fees.fee_tokens[] | [ .average_gas_price, .denom ] | join("")' ${CHAIN_JSON} | paste -sd, -)"}
    NODE_KEY=${NODE_KEY:=}
    NODE_MODE=${NODE_MODE:=}
    MAX_PAYLOAD=${MAX_PAYLOAD:=}
    ADDR_BOOK_URL=${ADDR_BOOK_URL:=}
    PRIVATE_VALIDATOR_KEY=${PRIVATE_VALIDATOR_KEY:=}
    PRIVATE_PEER_IDS=${PRIVATE_PEER_IDS:=}
    PUBLIC_ADDRESS=${PUBLIC_ADDRESS:=}
    BOOTSTRAP_PEERS=${BOOTSTRAP_PEERS:=}
    UNCONDITIONAL_PEER_IDS=${UNCONDITIONAL_PEER_IDS:=}
    IS_SEED_NODE=${IS_SEED_NODE:="false"}
    IS_SENTRY=${IS_SENTRY:="false"}
    USE_HORCRUX=${USE_HORCRUX:="false"}
    SENTRIED_VALIDATOR=${SENTRIED_VALIDATOR:="false"}
    METRIC_NAMESPACE=${METRIC_NAMESPACE:="tendermint"}
}

# Identify and download the binaries for the given upgrades
download_binaries(){
    local name
    local info
    local binary_url

    if [ -f "${UPGRADE_JSON}" ]; then
        logger "Downloading binary identified in ${UPGRADE_JSON}..."
        info=$(jq  -r ".info | if type==\"string\" then . else .binaries.\"${ARCH}\" end" ${UPGRADE_JSON})
        if [ "${info}" = "{\"binaries\""* ]; then
            binary_url="$(echo $info | jq -r ".binaries.\"${ARCH}\"")"
            download_binary "${version}" "${binary_url}"
            link_cv_current "${version}"
        elif [ "${info}" = http:* ]; then
            binary_url="${info}"
            download_binary "${version}" "${binary_url}"
            link_cv_current "${version}"
        else
            name=$(jq  -r ".name" ${UPGRADE_JSON})
            recver="$(jq -r '.codebase.recommended_version' ${CHAIN_JSON})"
            for version in "${name}" "${info}", "${recver}"; do
                binary_url="${binary_url:="$(get_chain_json_binary "${version}")"}"
                if [ -n "${binary_url}" ]; then
                    download_binary "${version}" "${binary_url}"
                    link_cv_current "${version}"
                    break
                fi
            done
        fi
    else
        logger "Downloading binaries identified in ${CHAIN_JSON}..."
        for version in $(jq -r '.codebase.versions[] | .name' ${CHAIN_JSON}); do
            binary_url="$(get_chain_json_binary "${version}")"
            download_binary "${version}" "${binary_url}"
            link_cv_current "${version}"
        done 
    fi
}

get_chain_json_binary(){
    local version="$1"
    local binary_url
    if [ -n "$(jq -r ".codebase.versions[] | select(.name == \"${version}\") | .name" ${CHAIN_JSON})" ]; then
        echo "$(jq -r ".codebase.versions[] | select(.name == \"${version}\") | .binaries[\"${ARCH}\"]" ${CHAIN_JSON})" 
    elif [ -n "$(jq -r ".codebase.versions[] | select(.tag == \"${version}\") | .name" ${CHAIN_JSON})" ]; then
        echo "$(jq -r ".codebase.versions[] | select(.tag == \"${version}\") | .binaries[\"${ARCH}\"]" ${CHAIN_JSON})" 
    elif [ "$(jq -r ".codebase.binaries[\"${ARCH}\"]" ${CHAIN_JSON})" = *"${version}"* ]; then
        echo "$(jq -r ".codebase.binaries[\"${ARCH}\"]" ${CHAIN_JSON})" 
    fi
}

# Download the binary for the given upgrade
download_binary(){
    local upgrade="$1"
    local binary_url="$2"
    local bin_path="${CV_UPGRADES_DIR}/${upgrade}/bin"
    local binary="${bin_path}/${DAEMON_NAME}"
    if [ ! -f "${binary}" ]; then
        mkdir -p "${bin_path}"
        wget "${binary_url}" -O- | tar xz -C "${bin_path}"
    fi
}

# Link the given cosmosvisor upgrade directory to the cosmovisor current directory
link_cv_current(){
    local upgrade="$1"
    local upgrade_path="${CV_UPGRADES_DIR}/${upgrade}"
    if [ ! -e "${CV_CURRENT_DIR}" ]; then
        ln -s "${upgrade_path}" "${CV_CURRENT_DIR}"
    fi
    # Link the genesis directory if the upgrade is the genesis version (or no genesis version is set)
    if [ -z "${GENESIS_VERSION}" ] || [ "${GENESIS_VERSION}" = "${upgrade}" ]; then
        link_cv_genesis "${upgrade}"
    fi
}

# Link the given cosmosvisor upgrade directory to the cosmovisor genesis directory
link_cv_genesis(){
    local upgrade="$1"
    local upgrade_path="${CV_UPGRADES_DIR}/${upgrade}"
    if [ ! -e "${CV_GENESIS_DIR}" ]; then
        ln -s "${upgrade_path}" "${CV_GENESIS_DIR}"
    elif [ ! -e "${CV_GENESIS_DIR}/bin" ]; then
        ln -s "${upgrade_path}/bin" "${CV_GENESIS_DIR}/bin"
    elif [ ! -e "${CV_GENESIS_DIR}/bin/${DAEMON_NAME}" ]; then
        ln -s "${upgrade_path}/bin/${DAEMON_NAME}" "${CV_GENESIS_DIR}/bin/${DAEMON_NAME}"
    fi
}

# Initialize the node
initialize_node(){
    if [ ! -d "${CONFIG_DIR}" ] || [ ! -f "${GENESIS_FILE}" ]; then
        echo "Initializing node from scratch..."
        ${CV_CURRENT_DIR}/bin/${DAEMON_NAME} init "${MONIKER}" -o --home "${DAEMON_HOME}" --chain-id "${CHAIN_ID}"
    fi
    if [ ! -d "${DATA_DIR}" ]; then
        mkdir -p "${DATA_DIR}"
    fi
}

# Download the genesis file
download_genesis(){
    if [ ! -d "${CONFIG_DIR}" ]; then
        mkdir -p "${CONFIG_DIR}"
    fi

    if [ -n "${GENESIS_URL}" ]; then
        echo "Downloading genesis file..."
        if [ "${GENESIS_URL}" = *.tar.gz ]; then
            wget "${GENESIS_URL}" -O- | tar -xz > "${GENESIS_FILE}"
        elif [ "${GENESIS_URL}" = *.gz ]; then
            wget "${GENESIS_URL}" -O- | zcat > "${GENESIS_FILE}"
        else
            wget "${GENESIS_URL}" -O "${GENESIS_FILE}"
        fi
    fi
}

# Download the address book file
download_addrbook(){
    if [ -n "${ADDR_BOOK_URL}" ]; then
        echo "Downloading address book file..."
        wget "${ADDR_BOOK_URL}" -O "${ADDR_BOOK_FILE}"
    fi
}

# Set the node key
set_node_key(){
    if [ -n "${NODE_KEY}" ]; then
        echo "Using node key from env..."
        echo "${NODE_KEY}" | base64 -d > "${NODE_KEY_FILE}"
    fi
}

# Set the private validator key
set_private_validator_key(){
    if [ -n "${PRIVATE_VALIDATOR_KEY}" ]; then
        echo "Using private key from env..."
        echo "${PRIVATE_VALIDATOR_KEY}" | base64 -d > "${PV_KEY_FILE}"
    fi
}

# Modify the client.toml file
modify_client_toml(){
    sed -e "s|^chain-id *=.*|chain-id = \"${CHAIN_ID}\"|" -i "${CLIENT_TOML}"
}

# Modify the config.toml file
modify_config_toml(){
    cp "${CONFIG_TOML}" "${CONFIG_TOML}.bak"
    sed -e "s|^laddr *=\s*\"tcp:\/\/127.0.0.1|laddr = \"tcp:\/\/0.0.0.0|" -i "${CONFIG_TOML}"
    sed -e "s|^log_format *=.*|log_format = \"${LOG_FORMAT}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^timeout_broadcast_tx_commit *=.*|timeout_broadcast_tx_commit = \"${TIMEOUT_BROADCAST_TX_COMMIT}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^max_body_bytes *=.*|max_body_bytes = ${MAX_BODY_BYTES}|" -i "${CONFIG_TOML}"
    sed -e "s|^dial_timeout *=.*|dial_timeout = \"${DIAL_TIMEOUT}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^chunk_fetchers *=.*|chunk_fetchers = \"${CHUNK_FETCHERS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^seeds *=.*|seeds = \"${SEEDS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^persistent_peers *=.*|persistent_peers = \"${PERSISTENT_PEERS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^unconditional_peer_ids *=.*|unconditional_peer_ids = \"${UNCONDITIONAL_PEER_IDS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^bootstrap-peers *=.*|bootstrap-peers = \"${BOOTSTRAP_PEERS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^allow-duplicate-ip *=.*|allow-duplicate-ip = ${ALLLOW_DUPLICATE_IP}|" -i "${CONFIG_TOML}"
    sed -e "s|^addr-book-strict *=.*|addr-book-strict = ${ADDR_BOOK_STRICT}|" -i "${CONFIG_TOML}"
    sed -e "s|^use-p2p *=.*|use-p2p = true|" -i "${CONFIG_TOML}"
    sed -e "s|^prometheus *=.*|prometheus = true|" -i "${CONFIG_TOML}"
    sed -e "s|^namespace *=.*|namespace = \"${METRIC_NAMESPACE}\"|" -i "${CONFIG_TOML}"

    if [ -n "${NODE_MODE}" ]; then
        sed -e "s|^mode *=.*|mode = \"${NODE_MODE}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${MAX_PAYLOAD}" ]; then
        sed -e "s|^max-packet-msg-payload-size *=.*|max-packet-msg-payload-size = ${MAX_PAYLOAD}|" -i "${CONFIG_TOML}"
    fi

    if [ "${IS_SEED_NODE}" = "true" ]; then
        sed -e "s|^seed_mode *=.*|seed_mode = true|" -i "${CONFIG_TOML}"
    fi

    if [ "${IS_SENTRY}" = "true" ] || [ -n "${PRIVATE_PEER_IDS}" ]; then
        sed -e "s|^private_peer_ids *=.*|private_peer_ids = \"${PRIVATE_PEER_IDS}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${PUBLIC_ADDRESS}" ]; then
        echo "Setting public address to ${PUBLIC_ADDRESS}"
        sed -e "s|^external_address *=.*|external_address = \"${PUBLIC_ADDRESS}\"|" -i "${CONFIG_TOML}"
    fi

    if [ "${USE_HORCRUX}" = "true" ]; then
        sed -e "s|^priv_validator_laddr *=.*|priv_validator_laddr = \"tcp://[::]:23756\"|" \
            -e "s|^laddr *= \"\"|laddr = \"tcp://[::]:23756\"|" \
            -i "${CONFIG_TOML}"
    fi

    if [ -n "${DB_BACKEND}" ]; then
        sed -e "s|^db_backend *=.*|db_backend = \"${DB_BACKEND}\"|" -i "${CONFIG_TOML}"
    fi

    if [ "${SENTRIED_VALIDATOR}" = "true" ]; then
        sed -e "s|^pex *=.*|pex = false|" -i "${CONFIG_TOML}"
    fi
}

modify_app_toml(){
    cp "${APP_TOML}" "${APP_TOML}.bak" 
    sed -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"${MINIMUM_GAS_PRICES}\"|" -i "${APP_TOML}"
    sed -e "s|^pruning *=.*|pruning = \"${PRUNING_STRATEGY}\"|" -i "${APP_TOML}"
    sed -e "s|^pruning-keep-recent *=.*|pruning-keep-recent = \"${PRUNING_KEEP_RECENT}\"|" -i "${APP_TOML}"
    sed -e "s|^pruning-interval *=.*|pruning-interval = \"${PRUNING_INTERVAL}\"|" -i "${APP_TOML}"
    sed -e "s|^pruning-keep-every *=.*|pruning-keep-every = \"${PRUNING_KEEP_EVERY}\"|" -i "${APP_TOML}"
    sed -e "s|^snapshot-interval *=.*|snapshot-interval = \"${SNAPSHOT_INTERVAL}\"|" -i "${APP_TOML}"
    sed -e "s|^snapshot-keep-recent *=.*|snapshot-keep-recent = \"${KEEP_SNAPSHOTS}\"|" -i "${APP_TOML}"
    sed -e "s|^contract-memory-cache-size *=.*|contract-memory-cache-size = \"${CONTRACT_MEMORY_CACHE_SIZE}\"|" -i "${APP_TOML}"

    if [ -n "${DB_BACKEND}" ]; then
        sed -e "s|^app-db-backend *=.*|app-db-backend = \"${DB_BACKEND}\"|" -i "${APP_TOML}"
    fi

    if [ "${ENABLE_API}" = "true" ]; then  
        sed -e '/^\[api\]/,/\[rosetta\]/ s|^enable *=.*|enable = true|' -i "${APP_TOML}"
    fi

    if [ "${ENABLE_SWAGGER}" = "true" ]; then
        sed -e '/^\[api\]/,/\[rosetta\]/ s|^swagger *=.*|swagger = true|' -i "${APP_TOML}"
    fi
}

configure_state_sync(){
    if [ ${STATE_SYNC_ENABLED} = "true" ]; then
        echo "State sync is enabled, attempting to fetch snapshot info..."
        if [ -z "${FORCE_SNAPSHOT_HEIGHT}" ]; then
            LATEST_HEIGHT=$(curl -s ${STATE_SYNC_RPC}/block | jq -r .result.block.header.height)
            if [ "${LATEST_HEIGHT}" = "null" ]; then
                # Maybe Tendermint 0.35+?
                LATEST_HEIGHT=$(curl -s ${STATE_SYNC_RPC}/block | jq -r .block.header.height)
            fi

            SYNC_BLOCK_HEIGHT=$((${LATEST_HEIGHT} - ${TRUST_LOOKBACK}))
        else
            SYNC_BLOCK_HEIGHT=${FORCE_SNAPSHOT_HEIGHT}
        fi
        SYNC_BLOCK_HASH=$(curl -s "${STATE_SYNC_RPC}/block?height=${SYNC_BLOCK_HEIGHT}" | jq -r .result.block_id.hash)
        if [ "${SYNC_BLOCK_HASH}" = "null" ]; then
            # Maybe Tendermint 0.35+?
            SYNC_BLOCK_HASH=$(curl -s "${STATE_SYNC_RPC}/block?height=${SYNC_BLOCK_HEIGHT}" | jq -r .block_id.hash)
        fi
    fi

    if [ -n "${SYNC_BLOCK_HASH}" ]; then
        if [ -z "${STATE_SYNC_WITNESSES}" ]; then
            STATE_SYNC_WITNESSES=${STATE_SYNC_RPC}
        fi

        echo ""
        echo "Using state sync from with the following settings:"
        sed -i.bak -e "s/^enable *=.*/enable = true/" "${CONFIG_TOML}"
        sed -i.bak -e "s#^rpc_servers *=.*#rpc_servers = \"${STATE_SYNC_RPC},${STATE_SYNC_WITNESSES}\"#" "${CONFIG_TOML}"
        sed -i.bak -e "s#^rpc-servers *=.*#rpc-servers = \"${STATE_SYNC_RPC},${STATE_SYNC_WITNESSES}\"#" "${CONFIG_TOML}"
        sed -i.bak -e "s|^trust_height *=.*|trust_height = ${SYNC_BLOCK_HEIGHT}|" "${CONFIG_TOML}"
        sed -i.bak -e "s|^trust-height *=.*|trust-height = ${SYNC_BLOCK_HEIGHT}|" "${CONFIG_TOML}"
        sed -i.bak -e "s|^trust_hash *=.*|trust_hash = \"${SYNC_BLOCK_HASH}\"|" "${CONFIG_TOML}"
        sed -i.bak -e "s|^trust-hash *=.*|trust-hash = \"${SYNC_BLOCK_HASH}\"|" "${CONFIG_TOML}"
        # sed -i.bak -e "s/^trust_period *=.*/trust_period = \"168h\"/" "${CONFIG_TOML}"

        cat "${CONFIG_TOML}" | grep "enable ="
        cat "${CONFIG_TOML}" | grep -A 2 -B 2 trust_hash

    elif [ ${STATE_SYNC_ENABLED} = 'true' ]; then
        echo "Failed to look up sync snapshot, falling back to full sync..."
    fi

    if [ -n "${RESET_ON_START}" ]; then
        cp "${DATA_DIR}/priv_validator_state.json" /root/priv_validator_state.json.backup
        rm -rf "${DATA_DIR}"
        mkdir -p "${DATA_DIR}"
        mv /root/priv_validator_state.json.backup "${DATA_DIR}/priv_validator_state.json"
    elif [ -n "${PRUNE_ON_START}" ]; then
        if [ -n "${COSMPRUND_APP}" ]; then
            cosmprund-${DB_BACKEND} prune ${DATA_DIR} --app=${COSMPRUND_APP} --blocks=${PRUNING_KEEP_RECENT} --versions=${PRUNING_KEEP_RECENT}
        else
            cosmprund-${DB_BACKEND} prune ${DATA_DIR} --blocks=${PRUNING_KEEP_RECENT} --versions=${PRUNING_KEEP_RECENT}
        fi
    fi
}

if [ "$(basename $0)" = "entrypoint.sh" ]; then
    main
    exec $@
fi