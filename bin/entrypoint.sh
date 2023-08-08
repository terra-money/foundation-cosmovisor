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
APP_TOML="${CONFIG_DIR}/app.toml"
CLIENT_TOML="${CONFIG_DIR}/client.toml"
CONFIG_TOML="${CONFIG_DIR}/config.toml"
GENESIS_FILE="${CONFIG_DIR}/genesis.json"
NODE_KEY_FILE="${CONFIG_DIR}/node_key.json"
PV_KEY_FILE="${CONFIG_DIR}/priv_validator_key.json"
ADDR_BOOK_FILE="${CONFIG_DIR}/addrbook.json"

# Cosmovisor directory
COSMOVISOR_DIR="${DAEMON_HOME}/cosmovisor"
CV_CURRENT_DIR="${COSMOVISOR_DIR}/current"
CV_GENESIS_DIR="${COSMOVISOR_DIR}/genesis"
CV_UPGRADES_DIR="${COSMOVISOR_DIR}/upgrades"

GENESIS_BINARY_URL=${GENESIS_BINARY_URL:=""}
LIBRARY_URLS=${LIBRARY_URLS:=""}
BINARY_INFO_URL=${BINARY_INFO_URL:=""}
HALT_HEIGHT=${HALT_HEIGHT:=""}

SUPERVISOR_ENABLED=${SUPERVISOR_ENABLED:=""}

main(){
    get_system_info
    get_chain_json
    parse_chain_info
    prepare_versions
    download_libraries
    initialize_node
    reset_on_start
    set_node_key
    set_private_validator_key
    create_genesis
    download_addrbook
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
    curl -sSL "${CHAIN_JSON_URL}" -o "${CHAIN_JSON}"
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
    # choosing nothing as the default pruning strategy
    # to avoid accidentally pruning data on an archival node
    PRUNING_STRATEGY=${PRUNING_STRATEGY:="nothing"}
    SNAPSHOT_INTERVAL=${SNAPSHOT_INTERVAL:=${PRUNING_KEEP_EVERY}}
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
prepare_versions(){
    local name
    local info
    mkdir -p "${DATA_DIR}"

    # use recommended version from env or set in chain.json
    if [ "${PREFER_RECOMMENDED_VERSION}" = "true" ] && [ "${STATE_SYNC_ENABLED}" = "false" ]; then
        prepare_recommended_version

    # if state sync is enabled use recommended (or most recent) version
    elif [ ${STATE_SYNC_ENABLED} = "true" ]; then
        prepare_recommended_version
        get_wasm

    # if datadir has upgrade use that version
    elif [ -f "${UPGRADE_JSON}" ]; then
        prepare_upgrade_json_version

    # presume we are syncing from genesis otherwise
    else
        prepare_genesis_version
    fi
}

prepare_upgrade_json_version(){
    # If binary is defined in upgrade-info.json use it
    if [ -n "$(jq -r ".info | fromjson | .binaries.\"${ARCH}\"" ${UPGRADE_JSON})" ]; then
        logger "Using info from ${UPGRADE_JSON}..."
        create_cv_upgrade "$(cat ${UPGRADE_JSON})"

    # Otherwise look for missing binary in external file
    elif [ -n "${BINARY_INFO_URL}" ]; then
        logger "Binary URL is missing in upgrade-info.json, checking ${BINARY_INFO_URL}..."
        local name=$(jq  -r ".name" ${UPGRADE_JSON})
        local upgrade_info=$(curl -sSL "${BINARY_INFO_URL}" | jq ".[\"${CHAIN_ID}\"][] | select(.name == \"${name}\")")

        if [ -n "${upgrade_info}" ]; then
            create_cv_upgrade "${upgrade_info}"
        else
            logger "Binary URL is missing, update ${BINARY_INFO_URL} to continue."
        fi
    fi
}

prepare_recommended_version(){
    logger "Preparing recommended version ${RECOMMENDED_VERSION}..."
    prepare_chain_json_version "${RECOMMENDED_VERSION}"
    if [ ! -e "${CV_CURRENT_DIR}" ]; then
        if [ -f "${UPGRADE_JSON}" ]; then
            logger "Recommended version not found in ${CHAIN_JSON}, falling back to latest version..."
            prepare_last_available_version
        else
            logger "Recommended version not found in ${CHAIN_JSON}, falling back to first version..."
            prepare_first_available_version
        fi
    fi
}

get_chain_json_version(){
    local version="$1"
    if [ -n "$(jq -r ".codebase.versions[] | select(.tag == \"${version}\") | .tag" ${CHAIN_JSON})" ]; then
        jq -r ".codebase.versions[] | select(.tag == \"${version}\")" ${CHAIN_JSON}
    elif [ -n "$(jq -r ".codebase.versions[] | select(.name == \"${version}\") | .name" ${CHAIN_JSON})" ]; then
        jq -r ".codebase.versions[] | select(.name == \"${version}\")" ${CHAIN_JSON}
    elif [ -n "$(jq -r ".codebase.versions[] | select(.recommended_version == \"${version}\") | .recommended_version" ${CHAIN_JSON})" ]; then
        jq -r ".codebase.versions[] | select(.recommended_version == \"${version}\")" ${CHAIN_JSON}
    fi
}

prepare_chain_json_version(){
    local version="$1"
    logger "Looking for version ${version} in ${CHAIN_JSON}..."

    # get binary details for given version
    upgrade_info=$(get_chain_json_version "${version}" |
        jq "{\"name\": .name, \"height\": (.height // 0), \"info\": ({\"binaries\": .binaries} | tostring)}"
    )

    # install binary if found
    if [ -n "${upgrade_info}" ]; then
        create_cv_upgrade "${upgrade_info}"
    fi
}

prepare_last_available_version(){
    local upgrade_info=""
    logger "Preparing last available version identified in ${CHAIN_JSON}..."

    # try to get version without next_version_name set
    if [ -n "$(jq -r "first(.codebase.versions[] | .next_version_name // \"\")" ${CHAIN_JSON})" ]; then
        upgrade_info=$(jq "last(.codebase.versions[] |
            select(has("next_version_name") | not) |
            {\"name\": .name, \"height\": (.height // 0), \"info\": ({\"binaries\": .binaries} | tostring)})" \
            "${CHAIN_JSON}")
    fi

    # if last query fails simplify
    if [ -n "${upgrade_info}" ]; then
        upgrade_info="$(jq "last(.codebase.versions[] |
            {\"name\": .name, \"height\": (.height // 0), \"info\": ({\"binaries\": .binaries} | tostring)})" \
            "${CHAIN_JSON}" > "${upgrade_json}")"
    fi

    if [ -n "${upgrade_info}" ]; then
        create_cv_upgrade "${upgrade_info}"
    fi
}

prepare_genesis_version(){
    if [ -n "${GENESIS_BINARY_URL}" ]; then
        logger "Preparing genesis version defined with environment variables..."
        local upgrade_info="{
            \"name\": \"${GENESIS_VERSION}\",
            \"height\": 0,
            \"info\": \"{\\\"binaries\\\":{\\\"linux/amd64\\\":\\\"${GENESIS_BINARY_URL}\\\"}}\"
        }"
        create_cv_upgrade "${upgrade_info}"
    else
        logger "Preparing genesis version identified in ${CHAIN_JSON}..."
        prepare_chain_json_version "${GENESIS_VERSION}"
    fi
    if [ ! -L "${CV_GENESIS_DIR}" ]; then
        logger "Genesis version (${GENESIS_VERSION}) not found in ${CHAIN_JSON}, falling back to first version..."
        prepare_first_available_version
    else
        link_cv_current "${CV_GENESIS_DIR}"
    fi
}

prepare_first_available_version(){
    logger "Preparing first available version identified in ${CHAIN_JSON}..."
    local upgrade_info=$(jq "first(.codebase.versions[] |
        {\"name\": .name, \"height\": (.height // 0),  \"info\": ({\"binaries\": .binaries} | tostring)})" \
        "${CHAIN_JSON}")
    if [ -n "${upgrade_info}" ]; then
        create_cv_upgrade "${upgrade_info}"
    fi
}

create_cv_upgrade(){
    local upgrade_info="$1"
    local upgrade_name="$(echo "${upgrade_info}" | jq -r ".name")"
    local upgrade_height="$(echo "${upgrade_info}" | jq -r ".height")"
    local binary_url="$(echo "${upgrade_info}" | jq -r ".info | fromjson | .binaries.\"${ARCH}\"")"
    local upgrade_path="${CV_UPGRADES_DIR}/${upgrade_name}"
    local upgrade_json="${upgrade_path}/upgrade-info.json"
    local binary_file="${upgrade_path}/bin/${DAEMON_NAME}"
    logger "Found version ${upgrade_name}, Creating ${upgrade_path}..."
    mkdir -p "${upgrade_path}"
    if [ "${binary_url}" != "null" ]; then
        download_cv_current "${binary_url}" "${binary_file}"
    fi
    if [ ${upgrade_height} -gt 0 ]; then
        logger "Creating ${upgrade_json}..."
        echo "${upgrade_info}" > "${upgrade_json}"
        logger "Copying ${upgrade_json} to ${UPGRADE_JSON}..."
        cp "${upgrade_json}" "${UPGRADE_JSON}"
        link_cv_current "${upgrade_path}"
    else
        link_cv_genesis "${upgrade_path}"
    fi
}

# Link the given cosmosvisor upgrade directory to the cosmovisor current directory
link_cv_current(){
    local upgrade_path="$1"
    if [ -L "${CV_CURRENT_DIR}" ]; then
        logger "Removing existing ${CV_CURRENT_DIR}..."
        rm "${CV_CURRENT_DIR}"
    elif [ -e "${CV_CURRENT_DIR}" ]; then
        logger "Removing existing ${CV_CURRENT_DIR}..."
        rm -rf "${CV_CURRENT_DIR}"
    fi
    logger "Linking ${CV_CURRENT_DIR} to ${upgrade_path}..."
    ln -s "${upgrade_path}" "${CV_CURRENT_DIR}"
}

# Link the given cosmosvisor upgrade directory to the cosmovisor genesis directory
link_cv_genesis(){
    local upgrade_path="$1"
    if [ -e "${CV_GENESIS_DIR}" ]; then
        logger "Removing existing ${CV_GENESIS_DIR}..."
        rm -rf "${CV_GENESIS_DIR}"
    fi
    logger "Linking ${CV_GENESIS_DIR} to ${upgrade_path}"
    ln -s "${upgrade_path}" "${CV_GENESIS_DIR}"
}

# Download the binary for the given upgrade
download_cv_current(){
    local binary_url="$1"
    local binary_file="$2"
    local binary_path="$(dirname "${binary_file}")"

    logger "Downloading ${binary_url} to ${binary_file}..."
    mkdir -p "${upgrade_path}/bin"
    case ${binary_url} in
        *.tar.gz*)
            curl -sSL "${binary_url}" | tar xz -C "${binary_path}"
            ;;
        *)
            curl -sSL "${binary_url}" -o "${binary_file}"
            ;;
    esac
    chmod 0755 "${binary_file}"
    if [ "$(file -b ${binary_file})" = "JSON data" ]; then
        binary_url="$(jq -r ".binaries.\"${ARCH}\"" "${binary_file}")"
        download_cv_current "${binary_url}" "${binary_file}"
    fi
}

get_upgrade_json_version(){
    logger "Downloading binary identified in ${UPGRADE_JSON}..."
    binary_url="$(echo "${info}" | jq -r ".binaries.\"${ARCH}\"")"
    if [ "${info}" = "{\"binaries\""* ]; then
        download_version "${name}" "${binary_url}"
    elif [ "${info}" = http:* ]; then
        binary_url="${info}"
        download_version "${name}" "${binary_url}"
    elif [ -n "$(get_chain_json_version "${name}")" ]; then
        binary_url="$(get_chain_json_version "${name}")"
        download_version "${name}" "${binary_url}"
    else
        # fallback to recommended version
        get_recommended_version "${name}"
    fi
}

# Download required libraries
download_libraries(){
    if [ -n "${LIBRARY_URLS}" ]; then
        for url in ${LIBRARY_URLS}; do
            logger "Downloading library: $url..."
            curl -sSLO --output-dir "/usr/local/lib" "${url}"
        done
        export LD_LIBRARY_PATH="/usr/local/lib"
    fi
}

# Initialize the node
initialize_node(){
    # TODO: initialize in tmpdir and copy any missing files to the config dir
    if [ ! -d "${CONFIG_DIR}" ] || [ ! -f "${GENESIS_FILE}" ]; then
        logger "Initializing node from scratch..."
        /usr/local/bin/cosmovisor run init "${MONIKER}" --home "${DAEMON_HOME}" --chain-id "${CHAIN_ID}"
        rm "${GENESIS_FILE}"
    fi
}

# Create the genesis file
create_genesis(){
    if [ ! -d "${CONFIG_DIR}" ]; then
        mkdir -p "${CONFIG_DIR}"
    fi

    if [ ! -f "${GENESIS_FILE}" ] && [ -n "${GENESIS_URL}" ]; then
        logger "Downloading genesis file from ${GENESIS_URL}..."
        case "${GENESIS_URL}" in
            *.tar.gz)
                curl -sSL "${GENESIS_URL}" | tar -xzO > "${GENESIS_FILE}"
                ;;
            *.gz)
                curl -sSL "${GENESIS_URL}" | zcat > "${GENESIS_FILE}"
                ;;
            *)
                curl -sSL "${GENESIS_URL}" -o "${GENESIS_FILE}"
                ;;
        esac
    fi
}

# Download the address book file
download_addrbook(){
    if [ -n "${ADDR_BOOK_URL}" ]; then
        echo "Downloading address book file..."
        curl -sSL "${ADDR_BOOK_URL}" -o "${ADDR_BOOK_FILE}"
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
        latest_height=$(curl -sSL ${STATE_SYNC_RPC}/block | jq -r .result.block.header.height)
        if [ "${latest_height}" = "null" ]; then
            # Maybe Tendermint 0.35+?
            latest_height=$(curl -sSL ${STATE_SYNC_RPC}/block | jq -r .block.header.height)
        fi
        sync_block_height=$((${latest_height} - ${TRUST_LOOKBACK}))
    fi
    echo "${sync_block_height:=}"
}

get_sync_block_hash(){
    local sync_block_hash
    if [ -n "${SYNC_BLOCK_HEIGHT}" ] && [ "${STATE_SYNC_ENABLED}" = "true" ]; then
        sync_block_hash=$(curl -sSL "${STATE_SYNC_RPC}/block?height=${SYNC_BLOCK_HEIGHT}" | jq -r .result.block_id.hash)
        if [ "${sync_block_hash}" = "null" ]; then
            sync_block_hash=$(curl -sSL "${STATE_SYNC_RPC}/block?height=${SYNC_BLOCK_HEIGHT}" | jq -r .block_id.hash)
        fi
    fi
    echo "${sync_block_hash:=}"
}

# Modify the client.toml file
modify_client_toml(){
    if [ -f "${CLIENT_TOML}" ]; then
        sed -e "s|^chain-id *=.*|chain-id = \"${CHAIN_ID}\"|" -i "${CLIENT_TOML}"
    fi
}

# Modify the config.toml file
modify_config_toml(){
    cp "${CONFIG_TOML}" "${CONFIG_TOML}.bak"
    sed -e "s|^laddr *=\s*\"tcp:\/\/127.0.0.1|laddr = \"tcp:\/\/0.0.0.0|" -i "${CONFIG_TOML}"
    sed -e "s|^log.format *=.*|log_format = \"${LOG_FORMAT}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^timeout.broadcast.tx.commit *=.*|timeout_broadcast_tx_commit = \"${TIMEOUT_BROADCAST_TX_COMMIT}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^max.body.bytes *=.*|max_body_bytes = ${MAX_BODY_BYTES}|" -i "${CONFIG_TOML}"
    sed -e "s|^dial.timeout *=.*|dial_timeout = \"${DIAL_TIMEOUT}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^fast.sync *=.*|fast_sync = \"${FAST_SYNC}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^chunk.fetchers *=.*|chunk_fetchers = \"${CHUNK_FETCHERS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^seeds *=.*|seeds = \"${SEEDS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^persistent.peers *=.*|persistent_peers = \"${PERSISTENT_PEERS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^unconditional.peer.ids *=.*|unconditional_peer_ids = \"${UNCONDITIONAL_PEER_IDS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^bootstrap.peers *=.*|bootstrap_peers = \"${BOOTSTRAP_PEERS}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^allow.duplicate.ip *=.*|allow_duplicate_ip = ${ALLOW_DUPLICATE_IP}|" -i "${CONFIG_TOML}"
    sed -e "s|^addr.book.strict *=.*|addr_book_strict = ${ADDR_BOOK_STRICT}|" -i "${CONFIG_TOML}"
    sed -e "s|^max.num.inbound.peers *=.*|max_num_inbound_peers = ${MAX_NUM_INBOUND_PEERS}|" -i "${CONFIG_TOML}"
    sed -e "s|^max.num.outbound.peers *=.*|max_num_outbound_peers = ${MAX_NUM_OUTBOUND_PEERS}|" -i "${CONFIG_TOML}"
    sed -e "s|^use.p2p *=.*|use_p2p = true|" -i "${CONFIG_TOML}"
    sed -e "s|^prometheus *=.*|prometheus = true|" -i "${CONFIG_TOML}"
    sed -e "s|^namespace *=.*|namespace = \"${METRIC_NAMESPACE}\"|" -i "${CONFIG_TOML}"

    if [ -n "${NODE_MODE}" ]; then
        sed -e "s|^mode *=.*|mode = \"${NODE_MODE}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${MAX_PAYLOAD}" ]; then
        sed -e "s|^max.packet.msg.payload.size *=.*|max_packet_msg_payload_size = ${MAX_PAYLOAD}|" -i "${CONFIG_TOML}"
    fi

    if [ "${IS_SEED_NODE}" = "true" ]; then
        sed -e "s|^seed.mode *=.*|seed_mode = true|" -i "${CONFIG_TOML}"
    fi

    if [ "${IS_SENTRY}" = "true" ] || [ -n "${PRIVATE_PEER_IDS}" ]; then
        sed -e "s|^private.peer.ids *=.*|private_peer_ids = \"${PRIVATE_PEER_IDS}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${PUBLIC_ADDRESS}" ]; then
        echo "Setting public address to ${PUBLIC_ADDRESS}"
        sed -e "s|^external.address *=.*|external_address = \"${PUBLIC_ADDRESS}\"|" -i "${CONFIG_TOML}"
    fi

    if [ "${USE_HORCRUX}" = "true" ]; then
        sed -e "s|^priv.validator.laddr *=.*|priv_validator_laddr = \"tcp://[::]:23756\"|" \
            -e "s|^laddr *= \"\"|laddr = \"tcp://[::]:23756\"|" \
            -i "${CONFIG_TOML}"
    fi

    if [ -n "${DB_BACKEND}" ]; then
        sed -e "s|^db.backend *=.*|db_backend = \"${DB_BACKEND}\"|" -i "${CONFIG_TOML}"
    fi

    if [ "${SENTRIED_VALIDATOR}" = "true" ]; then
        sed -e "s|^pex *=.*|pex = false|" -i "${CONFIG_TOML}"
    fi

    if [ ${STATE_SYNC_ENABLED} = "true" ]; then
        sed -e "s|^enable *=.*|enable = true|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${STATE_SYNC_RPC}" ] || [ -n "${STATE_SYNC_WITNESSES}" ]; then
        sed -e "s|^rpc.servers *=.*|rpc_servers = \"${STATE_SYNC_RPC},${STATE_SYNC_WITNESSES}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${SYNC_BLOCK_HEIGHT}" ]; then
        sed -e "s|^trust.height *=.*|trust_height = ${SYNC_BLOCK_HEIGHT}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${SYNC_BLOCK_HASH}" ]; then
        sed -e "s|^trust.hash *=.*|trust_hash = \"${SYNC_BLOCK_HASH}\"|" -i "${CONFIG_TOML}"
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
    sed -e "s|^rpc-max-body-bytes *=.*|rpc-max-body-bytes = \"${RPC_MAX_BODY_BYTES}\"|" -i "${APP_TOML}"

    if [ -n "${DB_BACKEND}" ]; then
        sed -e "s|^app-db-backend *=.*|app-db-backend = \"${DB_BACKEND}\"|" -i "${APP_TOML}"
    fi

    if [ "${ENABLE_API}" = "true" ]; then
        sed -e '/^\[api\]/,/\[rosetta\]/ s|^enable *=.*|enable = true|' -i "${APP_TOML}"
    fi

    if [ "${ENABLE_SWAGGER}" = "true" ]; then
        sed -e '/^\[api\]/,/\[rosetta\]/ s|^swagger *=.*|swagger = true|' -i "${APP_TOML}"
    fi

    if [ -n "${HALT_HEIGHT}" ]; then
        sed -e "s|^halt-height *=.*|halt-height = \"${HALT_HEIGHT}\"|" -i "${APP_TOML}"
    fi
}

get_wasm(){
    if [ -n "${WASM_URL}" ]; then
        logger "Downloading wasm files from ${WASM_URL}"
        wasm_base_dir=$(dirname ${WASM_DIR})
        mkdir -p "${wasm_base_dir}"
        curl -sSL "${WASM_URL}" | lz4 -c -d | tar -x -C "${wasm_base_dir}"
    fi
}

reset_on_start(){
    if [ "${RESET_ON_START}" = "true" ]; then
        logger "Reset on start set to: ${RESET_ON_START}"
        cp "${DATA_DIR}/priv_validator_state.json" /tmp/priv_validator_state.json.backup
        rm -rf "${DATA_DIR}"
        mkdir -p "${DATA_DIR}"
        mv /tmp/priv_validator_state.json.backup "${DATA_DIR}/priv_validator_state.json"
    fi
}

curlverify(){
    local url="$1"
    local target="$2"
    curl -sSL "${url}" -o "${target}"

    local query=$(echo ${orig_url} | sed -e 's/^.*?\?//')
    case query in
        checksum=sha256:*)
            local checksum=$(echo ${query} | sed -e 's/^checksum=sha256://')
            local actual=$(sha256sum "${target}" | awk '{print $1}')
            if [ "${actual}" != "${checksum}" ]; then
                logger "Checksum mismatch: ${actual} != ${checksum}"
                rm -rf "${target}"
                exit 1
            fi
        ;;
    esac
}

if [ "$(basename $0)" = "entrypoint.sh" ] || [ -n "${SUPERVISOR_ENABLED}" ]; then
    main 
    exec /bin/sh -c "trap : TERM INT; (while true; do $* && sleep 3; done) & wait"
fi
