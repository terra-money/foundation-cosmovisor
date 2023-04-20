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
WASM_DIR=${WASM_DIR:="${DATA_DIR}/wasm"}

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
    download_versions
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
    logger "Retrieving chain information from ${CHAIN_JSON_URL}..."
    # always download newest version of chain.json
    wget "${CHAIN_JSON_URL}" -O "${CHAIN_JSON}"
}

parse_chain_info(){
    logger "Parsing chain information..."
    export DAEMON_NAME=${DAEMON_NAME:="$(jq -r ".daemon_name" ${CHAIN_JSON})"}
    export CHAIN_ID=${CHAIN_ID:="$(jq -r ".chain_id" ${CHAIN_JSON})"}

    # Codebase Versions
    GENESIS_VERSION=${GENESIS_VERSION:="$(jq -r ".codebase.genesis.name" ${CHAIN_JSON})"}
    RECOMMENDED_VERSION=${RECOMMENDED_VERSION:="$(jq -r ".codebase.recommended_version" ${CHAIN_JSON})"}

    # app.toml
    CONTRACT_MEMORY_CACHE_SIZE=${CONTRACT_MEMORY_CACHE_SIZE:=8192}
    ENABLE_API=${ENABLE_API:=true}
    ENABLE_SWAGGER=${ENABLE_SWAGGER:=true}
    KEEP_SNAPSHOTS=${KEEP_SNAPSHOTS:=5}
    MONIKER=${MONIKER:="moniker"}
    MINIMUM_GAS_PRICES=${MINIMUM_GAS_PRICES:="$(jq -r '.fees.fee_tokens[] | [ .average_gas_price, .denom ] | join("")' ${CHAIN_JSON} | paste -sd, -)"}
    PRUNING_INTERVAL=${PRUNING_INTERVAL:=0}
    PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:=0}
    PRUNING_KEEP_EVERY=${PRUNING_KEEP_EVERY:=0}
    PRUNING_STRATEGY=${PRUNING_STRATEGY:=nothing}
    SNAPSHOT_INTERVAL=${SNAPSHOT_INTERVAL:=0}

    # config.toml
    ADDR_BOOK_STRICT=${ADDR_BOOK_STRICT:=false}
    ADDR_BOOK_URL=${ADDR_BOOK_URL:=}
    ALLOW_DUPLICATE_IP=${ALLOW_DUPLICATE_IP:=true}
    BOOTSTRAP_PEERS=${BOOTSTRAP_PEERS:=}
    CHUNK_FETCHERS=${CHUNK_FETCHERS:=30}
    DB_BACKEND=${DB_BACKEND:=goleveldb}
    DIAL_TIMEOUT=${DIAL_TIMEOUT:=5s}
    LOG_FORMAT=${LOG_FORMAT:=json}
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
    PRIVATE_VALIDATOR_KEY=${PRIVATE_VALIDATOR_KEY:='{"height": "0","round": 0,"step": 0}'}
    PRIVATE_PEER_IDS=${PRIVATE_PEER_IDS:=}
    PUBLIC_ADDRESS=${PUBLIC_ADDRESS:=}
    UNCONDITIONAL_PEER_IDS=${UNCONDITIONAL_PEER_IDS:=}
    USE_HORCRUX=${USE_HORCRUX:="false"}

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

# Identify and download the binaries for the given upgrades
download_versions(){
    local name
    local info

    # if state sync is enabled try to get latest version
    if [ ${STATE_SYNC_ENABLED} = "true" ]; then
        download_versions_statesync
        get_wasm
    else
        download_versions_default
    fi
}

download_versions_default(){
    # if upgrade.json is present try to get the binary found in upgrade.json
    if [ ! -e "${CV_CURRENT_DIR}" ] && [ -f "${UPGRADE_JSON}" ]; then
        get_upgrade_json_version
    fi

    # if upgrade.json is present but the binary is not found in upgrade.json
    # try to get the binary from chain.json rec version
    if [ ! -e "${CV_CURRENT_DIR}" ] && [ -f "${UPGRADE_JSON}" ] && [ ${STATE_SYNC_ENABLED} != "true" ]; then
        get_recommended_version
    fi

    # if upgrade.json is not present try to get all binaries from chain.json
    if [ ! -e "${CV_CURRENT_DIR}" ]; then
        get_available_versions_asc
    fi
}

download_versions_statesync(){
    if [ ! -e "${CV_CURRENT_DIR}" ]; then
        get_recommended_version
    fi
    if [ ! -e "${CV_CURRENT_DIR}" ]; then
        get_available_versions_dec
    fi
}

get_upgrade_json_version(){
    logger "Downloading binary identified in ${UPGRADE_JSON}..."
    local name=$(jq  -r ".name" ${UPGRADE_JSON})
    local info=$(jq  -r ".info | if type==\"string\" then . else .binaries.\"${ARCH}\" end" ${UPGRADE_JSON})
    local binary_url
    if [ "${info}" = "{\"binaries\""* ]; then
        binary_url="$(echo "${info}" | jq -r ".binaries.\"${ARCH}\"")"
        download_version "${name}" "${binary_url}"
        link_cv_current "${name}"
    elif [ "${info}" = http:* ]; then
        binary_url="${info}"
        download_version "${name}" "${binary_url}"
        link_cv_current "${name}"
    fi
}

get_recommended_version(){
    logger "Downloading recommended version identified in ${CHAIN_JSON}..."
    local binary_url="$(get_chain_json_version "${RECOMMENDED_VERSION}")"
    if [ -z "${binary_url}" ]; then
        binary_url="$(get_chain_json_version "$(echo "${RECOMMENDED_VERSION}" | sed -e "s/^v//")")"
    fi
    if [ -n "${binary_url}" ]; then
        download_version "${RECOMMENDED_VERSION}" "${binary_url}"
        link_cv_current "${RECOMMENDED_VERSION}"
    fi
}

get_available_versions_asc(){
    logger "Downloading oldest to newest versions identified in ${CHAIN_JSON}..."
    local versions=$(jq -r '.codebase.versions[] | .name' ${CHAIN_JSON}) 
    get_available_versions "${versions}"
}

get_available_versions_dec(){
    logger "Downloading newest to oldest versions identified in ${CHAIN_JSON}..."
    local versions=$(jq -r '.codebase.versions[] | .name' ${CHAIN_JSON} | tac) 
    get_available_versions "${versions}"
}

get_available_versions(){
    logger "Downloading all versions identified in ${CHAIN_JSON}..."
    local versions="$1" 
    local binary_url
    for version in ${versions}; do
        binary_url="$(get_chain_json_version "${version}")"
        if [ -n "${binary_url}" ] && [ "${binary_url}" != "null" ]; then
            download_version "${version}" "${binary_url}"
            link_cv_current "${version}"
        fi
    done 
}

get_chain_json_version(){
    local version="$1"
    local binary_url
    if [ -n "$(jq -r ".codebase.versions[] | select(.tag == \"${version}\") | .tag" ${CHAIN_JSON})" ]; then
        echo "$(jq -r ".codebase.versions[] | select(.tag == \"${version}\") | .binaries[\"${ARCH}\"]" ${CHAIN_JSON})" 
    elif [ -n "$(jq -r ".codebase.versions[] | select(.name == \"${version}\") | .name" ${CHAIN_JSON})" ]; then
        echo "$(jq -r ".codebase.versions[] | select(.name == \"${version}\") | .binaries[\"${ARCH}\"]" ${CHAIN_JSON})" 
    elif [ -n "$(jq -r ".codebase.versions[] | select(.recommended_version == \"${version}\") | .recommended_version" ${CHAIN_JSON})" ]; then
        echo "$(jq -r ".codebase.versions[] | select(.recommended_version == \"${version}\") | .binaries[\"${ARCH}\"]" ${CHAIN_JSON})" 
    elif expr "$(jq -r ".codebase.binaries[\"${ARCH}\"]" ${CHAIN_JSON})" : "/${version}/"; then
        echo "$(jq -r ".codebase.binaries[\"${ARCH}\"]" ${CHAIN_JSON})" 
    fi
}

# Download the binary for the given upgrade
download_version(){
    local upgrade="$1"
    local binary_url="$2"
    local bin_path="${CV_UPGRADES_DIR}/${upgrade}/bin"
    local binary="${bin_path}/${DAEMON_NAME}"
    if [ ! -f "${binary}" ]; then
        mkdir -p "${bin_path}"
        logger "Downloading ${binary_url} to ${binary}..."
        case ${binary_url} in
            *.tar.gz*)
                wget "${binary_url}" -O- | tar xz -C "${bin_path}"
                ;;
            *)
                wget "${binary_url}" -O "${binary}"
                ;;
        esac
        chmod 0755 "${binary}"
    fi
}

# Link the given cosmosvisor upgrade directory to the cosmovisor current directory
link_cv_current(){
    local upgrade="$1"
    local upgrade_path="${CV_UPGRADES_DIR}/${upgrade}"
    if [ ! -e "${CV_CURRENT_DIR}" ]; then
        logger "Linking ${CV_CURRENT_DIR} to ${upgrade_path}"
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
        logger "Linking ${CV_GENESIS_DIR} to ${upgrade_path}"
        ln -s "${upgrade_path}" "${CV_GENESIS_DIR}"
    elif [ ! -e "${CV_GENESIS_DIR}/bin" ]; then
        logger "Linking ${CV_GENESIS_DIR}/bin to ${upgrade_path}/bin"
        ln -s "${upgrade_path}/bin" "${CV_GENESIS_DIR}/bin"
    elif [ ! -e "${CV_GENESIS_DIR}/bin/${DAEMON_NAME}" ]; then
        logger "Linking ${CV_GENESIS_DIR}/bin/${DAEMON_NAME} to ${upgrade_path}/bin/${DAEMON_NAME}"
        ln -s "${upgrade_path}/bin/${DAEMON_NAME}" "${CV_GENESIS_DIR}/bin/${DAEMON_NAME}"
    fi
}

# Initialize the node
initialize_node(){
    # TODO: initialize in tmpdir and copy any missing files to the config dir
    if [ ! -d "${CONFIG_DIR}" ] || [ ! -f "${GENESIS_FILE}" ]; then
        logger "Initializing node from scratch..."
        ${CV_CURRENT_DIR}/bin/${DAEMON_NAME} init "${MONIKER}" --home "${DAEMON_HOME}" --chain-id "${CHAIN_ID}" -o
        rm "${GENESIS_FILE}"
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

    if [ ! -f "${GENESIS_FILE}" ] && [ -n "${GENESIS_URL}" ]; then
        logger "Downloading genesis file from ${GENESIS_URL}..."
        case "${GENESIS_URL}" in
            *.tar.gz)
                wget "${GENESIS_URL}" -O- | tar -xz > "${GENESIS_FILE}"
                ;;
            *.gz)
                wget "${GENESIS_URL}" -O- | zcat > "${GENESIS_FILE}"
                ;;
            *)
                wget "${GENESIS_URL}" -O "${GENESIS_FILE}"
                ;;
        esac
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

get_sync_block_height(){
    local latest_height
    local sync_block_height
    if [ "${STATE_SYNC_ENABLED}" = "true" ]; then
        latest_height=$(wget ${STATE_SYNC_RPC}/block -O- | jq -r .result.block.header.height)
        if [ "${latest_height}" = "null" ]; then
            # Maybe Tendermint 0.35+?
            latest_height=$(wget ${STATE_SYNC_RPC}/block -O- | jq -r .block.header.height)
        fi
        sync_block_height=$((${latest_height} - ${TRUST_LOOKBACK}))
    fi
    echo "${sync_block_height:=}"
}

get_sync_block_hash(){
    local sync_block_hash
    if [ -n "${SYNC_BLOCK_HEIGHT}" ] && [ "${STATE_SYNC_ENABLED}" = "true" ]; then
        sync_block_hash=$(wget "${STATE_SYNC_RPC}/block?height=${SYNC_BLOCK_HEIGHT}" -O- | jq -r .result.block_id.hash)
        if [ "${sync_block_hash}" = "null" ]; then
            sync_block_hash=$(wget "${STATE_SYNC_RPC}/block?height=${SYNC_BLOCK_HEIGHT}" -O- | jq -r .block_id.hash)
        fi
    fi
    echo "${sync_block_hash:=}"
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
    sed -e "s|^allow-duplicate-ip *=.*|allow-duplicate-ip = ${ALLOW_DUPLICATE_IP}|" -i "${CONFIG_TOML}"
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

    if [ ${STATE_SYNC_ENABLED} = "true" ]; then
        sed -e "s|^enable *=.*|enable = true|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${STATE_SYNC_RPC}" ] || [ -n "${STATE_SYNC_WITNESSES}" ]; then
        sed -e "s|^rpc_servers *=.*|rpc_servers = \"${STATE_SYNC_RPC},${STATE_SYNC_WITNESSES}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${SYNC_BLOCK_HEIGHT}" ]; then
        sed -e "s|^trust_height *=.*|trust_height = ${SYNC_BLOCK_HEIGHT}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${SYNC_BLOCK_HASH}" ]; then
        sed -e "s|^trust_hash *=.*|trust_hash = \"${SYNC_BLOCK_HASH}\"|" -i "${CONFIG_TOML}"
    fi
    # sed -e "s|^trust_period *=.*|trust_period = \"168h\"|" -i "${CONFIG_TOML}"
}

modify_app_toml(){
    cp "${APP_TOML}" "${APP_TOML}.bak" 
    sed -e "s|^moniker *=.*|moniker = \"${MONIKER}\"|" -i "${APP_TOML}"
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

get_wasm(){
    if [ -n "${WASM_URL}" ]; then
        logger "Downloading wasm files from ${WASM_URL}"
        wasm_base_dir=$(dirname ${WASM_DIR})
        mkdir -p "${wasm_base_dir}"
        wget "${WASM_URL}" -O- | lz4 -c -d | tar -x -C "${wasm_base_dir}"
    fi
}


reset_on_start(){
    if [ -n "${RESET_ON_START}" ]; then
        logger "Reset on start set to: ${RESET_ON_START}"
        cp "${DATA_DIR}/priv_validator_state.json" /root/priv_validator_state.json.backup
        rm -rf "${DATA_DIR}"
        mkdir -p "${DATA_DIR}"
        mv /root/priv_validator_state.json.backup "${DATA_DIR}/priv_validator_state.json"
    fi
}

if [ "$(basename $0)" = "entrypoint.sh" ]; then
    main
    exec "$@"
fi
