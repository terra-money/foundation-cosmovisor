#!/bin/bash

set -euo pipefail

export DEBUG=${DEBUG:=""}
if [ -n "${DEBUG}" ]; then
    set -x
fi

export DAEMON_HOME=${DAEMON_HOME:="$(pwd)"}
export CHAIN_HOME=${CHAIN_HOME:=$DAEMON_HOME}
export CHAIN_JSON="/etc/default/chain.json"
export UPGRADES_JSON="/etc/default/upgrades.yml"

# Shared/tmp directory
export SHARED_DIR=${SHARED_DIR:="${CHAIN_HOME}/shared"}
export TEMP_DIR=${TEMP_DIR:="${CHAIN_HOME}/tmp"}
export SNAPSHOTS_DIR="${SHARED_DIR}/snapshots"

# data directory
export DATA_DIR="${CHAIN_HOME}/data"
export WASM_DIR=${WASM_DIR:="${DATA_DIR}/wasm"}
export UPGRADE_INFO_JSON="${DATA_DIR}/upgrade-info.json"

# Config directory
export CONFIG_DIR="${CHAIN_HOME}/config"
export APP_TOML="${CONFIG_DIR}/app.toml"
export CLIENT_TOML="${CONFIG_DIR}/client.toml"
export CONFIG_TOML="${CONFIG_DIR}/config.toml"
export GENESIS_FILE="${CONFIG_DIR}/genesis.json"
export NODE_KEY_FILE="${CONFIG_DIR}/node_key.json"
export PV_KEY_FILE="${CONFIG_DIR}/priv_validator_key.json"
export ADDR_BOOK_FILE="${CONFIG_DIR}/addrbook.json"

parse_chain_info(){
    if [ ! -f "${CHAIN_JSON}" ]; then
        export CHAIN_NETWORK
        getchaininfo.py
    fi

    logger "Parsing chain information..."
    if [ -f "${CHAIN_JSON}" ]; then
        export DAEMON_NAME=${DAEMON_NAME:="$(jq -r ".daemon_name" ${CHAIN_JSON})"}
        export CHAIN_ID=${CHAIN_ID:="$(jq -r ".chain_id" ${CHAIN_JSON})"}
        MINIMUM_GAS_PRICES=${MINIMUM_GAS_PRICES:="$(jq -r '.fees.fee_tokens[] | [ .average_gas_price, .denom ] | join("")' ${CHAIN_JSON} | paste -sd, -)"}
        GENESIS_URL=${GENESIS_URL:="$(jq -r ".codebase.genesis.genesis_url" ${CHAIN_JSON})"}
        PERSISTENT_PEERS=${PERSISTENT_PEERS:="$(jq -r '.peers.persistent_peers[] | [.id, .address] | join("@")' ${CHAIN_JSON} | paste -sd, -)"}
        SEEDS=${SEEDS:="$(jq -r '.peers.seeds[] | [.id, .address] | join("@")' ${CHAIN_JSON} | paste -sd, -)"}
    else
        export CHAIN_ID=${CHAIN_ID:="${CHAIN_NAME}-${CHAIN_NETWORK}"}
        export DAEMON_NAME=${DAEMON_NAME:="${CHAIN_NAME}d"}
    fi


    # State sync
    STATE_SYNC_ENABLED=${STATE_SYNC_ENABLED:="$([ -n "${STATE_SYNC_RPC:=}" ] && echo "true" || echo "false")"}
    SYNC_BLOCK_HEIGHT=${SYNC_BLOCK_HEIGHT:="${FORCE_SNAPSHOT_HEIGHT:="$(get_sync_block_height)"}"}
    SYNC_BLOCK_HASH=${SYNC_BLOCK_HASH:="$(get_sync_block_hash)"}
}

logger(){
    echo "$*" | ts '[%Y-%m-%d %H:%M:%S]'
}

prepare(){
    parse_chain_info
    ensure_chain_home
    initialize_version
    initialize_node
    delete_data_dir
    create_directories
    load_data_from_image
    prepare_statesync
    set_node_key
    set_validator_key
    download_genesis
    download_addrbook
    setpruning.py
    modify_client_toml
    modify_config_toml
    modify_app_toml
}

start(){
    local command="$*"
    if [[ "${command}" != *"cosmovisor run start"* ]]; then
        exec /usr/bin/dumb-init -- "$@"
    fi
    export EXTRA_ARGS=${EXTRA_ARGS:="${command#*cosmovisor run start}"}
    exec /usr/bin/supervisord -c /etc/supervisord.conf
}

ensure_chain_home(){
    mkdir -p "${CHAIN_HOME}"
    chown -R cosmovisor:cosmovisor "${CHAIN_HOME}"
    if [ "${CHAIN_HOME}" != "${DAEMON_HOME}" ]; then
        ln -s ${CHAIN_HOME}/data ${DAEMON_HOME}/data;
    fi
}

initialize_version(){
    export  STATE_SYNC_ENABLED CHAIN_JSON_URL BINARY_URL BINARY_VERSION RESTORE_SNAPSHOT
    initversion.py
    if [ $? != 0 ]; then
        exit $?
    fi
    chown -R cosmovisor:cosmovisor "${DAEMON_HOME}/cosmovisor"
}

# Initialize the node
initialize_node(){
    # TODO: initialize in tmpdir and copy any missing files to the config dir
    if [ ! -d "${CONFIG_DIR}" ] || [ ! -f "${GENESIS_FILE}" ]; then
        logger "Initializing node from scratch..."
        mkdir -p "${DATA_DIR}"
        chown -R cosmovisor:cosmovisor "${DATA_DIR}"
        /usr/local/bin/cosmovisor run init "${MONIKER:="moniker"}" --home "${CHAIN_HOME}" --chain-id "${CHAIN_ID}"
        chown -R cosmovisor:cosmovisor "${CONFIG_DIR}"
        if [ -f "${GENESIS_FILE}" ]; then
            rm "${GENESIS_FILE}"
        else
            echo "Failed to initialize node." >&2
            exit $?
        fi
    fi
}

delete_data_dir(){
    if [ "${RESET_ON_START:=}" = "true" ]; then
        logger "Reset on start set to: ${RESET_ON_START}"
        cp "${DATA_DIR}/priv_validator_state.json" /tmp/priv_validator_state.json.backup
        rm -rf "${DATA_DIR}"
        mkdir -p "${DATA_DIR}"
        mv /tmp/priv_validator_state.json.backup "${DATA_DIR}/priv_validator_state.json"
        chown -R cosmovisor:cosmovisor "${DATA_DIR}"
    fi
}

create_directories(){
    mkdir -p "${SHARED_DIR}"
    chown -R cosmovisor:cosmovisor "${SHARED_DIR}"
    mkdir -p "${TEMP_DIR}"
    chown -R cosmovisor:cosmovisor "${TEMP_DIR}"
    chmod -R 777 "${TEMP_DIR}"
}

# Set the node key
set_node_key(){
    if [ -n "${NODE_KEY:=}" ]; then
        echo "Using node key from env..."
        echo "${NODE_KEY}" | base64 -d > "${NODE_KEY_FILE}"
        chown cosmovisor:cosmovisor ${NODE_KEY_FILE}*
    fi
}

# Set the private validator key
set_validator_key(){
    if [ -n "${PRIVATE_VALIDATOR_KEY:=}" ]; then
        echo "Using private key from env..."
        echo "${PRIVATE_VALIDATOR_KEY}" | base64 -d > "${PV_KEY_FILE}"
        chown cosmovisor:cosmovisor ${PV_KEY_FILE}*
    fi
}

# Retrieve the genesis file
download_genesis(){
    if [ ! -d "${CONFIG_DIR}" ]; then
        mkdir -p "${CONFIG_DIR}"
        chown cosmovisor:cosmovisor "${CONFIG_DIR}"
    fi

    if [ ! -f "${GENESIS_FILE}" ] && [ -n "${GENESIS_URL}" ]; then
        logger "Downloading genesis file from ${GENESIS_URL}..."
        case "${GENESIS_URL}" in
            *.tar.gz)
                curl -sSL "${GENESIS_URL}" | tar -xz -C "${CONFIG_DIR}" 2>/dev/null
                if [ ! -f "${GENESIS_FILE}" ]; then
                    mv ${CONFIG_DIR}/*genesis*.json ${GENESIS_FILE}
                fi
                ;;
            *.gz)
                curl -sSL "${GENESIS_URL}" | zcat > "${GENESIS_FILE}"
                ;;
            *)
                curl -sSL "${GENESIS_URL}" -o "${GENESIS_FILE}"
                ;;
        esac
        chown cosmovisor:cosmovisor ${GENESIS_FILE}*
    fi
}

# Download the address book file
download_addrbook(){
    if [ -n "${ADDR_BOOK_URL:=}" ]; then
        echo "Downloading address book file..."
        curl -sSL "${ADDR_BOOK_URL}" -o "${ADDR_BOOK_FILE}"
        chown cosmovisor:cosmovisor ${ADDR_BOOK_FILE}*
    fi
}

# Modify the client.toml file
modify_client_toml(){
    if [ -f "${CLIENT_TOML}" ]; then
        sed -e "s|^chain-id *=.*|chain-id = \"${CHAIN_ID}\"|" -i "${CLIENT_TOML}"
    fi
    chown cosmovisor:cosmovisor ${CLIENT_TOML}*
}

# Modify the config.toml file
modify_config_toml(){
    # config.toml
    cp "${CONFIG_TOML}" "${CONFIG_TOML}.bak"
    sed -e "s|^laddr *=\s*\"tcp:\/\/127.0.0.1|laddr = \"tcp:\/\/0.0.0.0|" -i "${CONFIG_TOML}"
    sed -e "s|^log.format *=.*|log_format = \"${LOG_FORMAT:=json}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^timeout.broadcast.tx.commit *=.*|timeout_broadcast_tx_commit = \"${TIMEOUT_BROADCAST_TX_COMMIT:=45s}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^dial.timeout *=.*|dial_timeout = \"${DIAL_TIMEOUT:="5s"}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^fast.sync *=.*|fast_sync = \"${FAST_SYNC:="true"}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^chunk.fetchers *=.*|chunk_fetchers = \"${CHUNK_FETCHERS:="30"}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^seeds *=.*|seeds = \"${SEEDS:=}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^persistent.peers *=.*|persistent_peers = \"${PERSISTENT_PEERS:=}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^unconditional.peer.ids *=.*|unconditional_peer_ids = \"${UNCONDITIONAL_PEER_IDS:=}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^bootstrap.peers *=.*|bootstrap_peers = \"${BOOTSTRAP_PEERS:=}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^allow.duplicate.ip *=.*|allow_duplicate_ip = ${ALLOW_DUPLICATE_IP:="true"}|" -i "${CONFIG_TOML}"
    sed -e "s|^addr.book.strict *=.*|addr_book_strict = ${ADDR_BOOK_STRICT:="false"}|" -i "${CONFIG_TOML}"
    sed -e "s|^max.num.inbound.peers *=.*|max_num_inbound_peers = ${MAX_NUM_INBOUND_PEERS:=20}|" -i "${CONFIG_TOML}"
    sed -e "s|^max.num.outbound.peers *=.*|max_num_outbound_peers = ${MAX_NUM_OUTBOUND_PEERS:=40}|" -i "${CONFIG_TOML}"
    sed -e "s|^use.p2p *=.*|use_p2p = true|" -i "${CONFIG_TOML}"
    sed -e "s|^prometheus *=.*|prometheus = true|" -i "${CONFIG_TOML}"
    sed -e "s|^namespace *=.*|namespace = \"${METRIC_NAMESPACE:="tendermint"}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^discard.abci.responses *=.*|discard_abci_responses = false|" -i "${CONFIG_TOML}"
    sed -e "s|^db.backend *=.*|db_backend = \"${DB_BACKEND:="goleveldb"}\"|" -i "${CONFIG_TOML}"
    sed -e "s|^max.body.bytes *=.*|max_body_bytes = ${MAX_BODY_BYTES:="2000000"}|" -i "${CONFIG_TOML}"

    if [ -n "${RPC_CORS_ALLOWED_ORIGIN:=}" ]; then
        sed -e "s|^cors.allowed.origins *=.*|cors_allowed_origins = ${RPC_CORS_ALLOWED_ORIGIN}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${NODE_MODE:=}" ]; then
        sed -e "s|^mode *=.*|mode = \"${NODE_MODE}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${MAX_HEADER_BYTES:=}" ]; then
        sed -e "s|^max.header.bytes *=.*|max_header_bytes = ${MAX_HEADER_BYTES}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${MAX_PAYLOAD:=}" ]; then
        sed -e "s|^max.packet.msg.payload.size *=.*|max_packet_msg_payload_size = ${MAX_PAYLOAD}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${INDEXER:=}" ]; then
        sed -e "s|^indexer *=.*|indexer = "\"${INDEXER}\""|" -i "${CONFIG_TOML}"
    fi

    if [ "${IS_SEED_NODE:=}" = "true" ]; then
        sed -e "s|^seed.mode *=.*|seed_mode = true|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${PRIVATE_PEER_IDS:=}" ]; then
        sed -e "s|^private.peer.ids *=.*|private_peer_ids = \"${PRIVATE_PEER_IDS}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${PUBLIC_ADDRESS:=}" ]; then
        echo "Setting public address to ${PUBLIC_ADDRESS}"
        sed -e "s|^external.address *=.*|external_address = \"${PUBLIC_ADDRESS}\"|" -i "${CONFIG_TOML}"
    fi

    if [ "${USE_HORCRUX:=}" = "true" ]; then
        sed -e "s|^priv.validator.laddr *=.*|priv_validator_laddr = \"tcp://[::]:23756\"|" \
            -e "s|^laddr *= \"\"|laddr = \"tcp://[::]:23756\"|" \
            -i "${CONFIG_TOML}"
    fi

    if [ "${SENTRIED_VALIDATOR:=}" = "true" ]; then
        sed -e "s|^pex *=.*|pex = false|" -i "${CONFIG_TOML}"
    fi

    if [ "${STATE_SYNC_ENABLED:=}" = "true" ]; then
        sed -e "s|^enable *=.*|enable = true|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${STATE_SYNC_RPC:=}" ]; then
        sed -e "s|^rpc.servers *=.*|rpc_servers = \"${STATE_SYNC_RPC:=},${STATE_SYNC_WITNESSES:=}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${SYNC_BLOCK_HEIGHT:=}" ]; then
        sed -e "s|^trust.height *=.*|trust_height = ${SYNC_BLOCK_HEIGHT}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${SYNC_BLOCK_HASH:=}" ]; then
        sed -e "s|^trust.hash *=.*|trust_hash = \"${SYNC_BLOCK_HASH}\"|" -i "${CONFIG_TOML}"
    fi
    # sed -e "s|^trust_period *=.*|trust_period = \"168h\"|" -i "${CONFIG_TOML}"

    if [ -n "${TIMEOUT_COMMIT:=}" ]; then
        sed -e "s|^timeout.commit *=.*|timeout_commit = \"${TIMEOUT_COMMIT}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${PROFILE:=}" ] && [ -n "${KUBERNETES_SERVICE_HOST:=}" ]; then
        k8speers.py
    fi
    chown cosmovisor:cosmovisor ${CONFIG_TOML}*
}

modify_app_toml(){
    cp "${APP_TOML}" "${APP_TOML}.bak"
    sed -e "s|^moniker *=.*|moniker = \"${MONIKER:="moniker"}\"|" -i "${APP_TOML}"
    sed -e "s|^snapshot-interval *=.*|snapshot-interval = \"${SNAPSHOT_INTERVAL:="2000"}\"|" -i "${APP_TOML}"
    sed -e "s|^snapshot-keep-recent *=.*|snapshot-keep-recent = \"${KEEP_SNAPSHOTS:="10"}\"|" -i "${APP_TOML}"
    sed -e "s|^contract-memory-cache-size *=.*|contract-memory-cache-size = \"${CONTRACT_MEMORY_CACHE_SIZE:="8192"}\"|" -i "${APP_TOML}"
    sed -e "s|^app-db-backend *=.*|app-db-backend = \"${DB_BACKEND:="goleveldb"}\"|" -i "${APP_TOML}"

    sed -e "s|^address *=.*:1317.*$|address = \"tcp:\/\/0.0.0.0:1317\"|" \
        -e "s|^address *=.*:8080.*$|address = \"0.0.0.0:8080\"|" \
        -e "s|^address *=.*:9090.*$|address = \"0.0.0.0:9090\"|" \
        -e "s|^address *=.*:9091.*$|address = \"0.0.0.0:9091\"|" \
        -i "${APP_TOML}"

    if [ -n "${PROFILE:=}" ]; then
        if [ -n "${PRUNING_STRATEGY:=}" ]; then
            sed -e "s|^pruning *=.*|pruning = \"${PRUNING_STRATEGY}\"|" -i "${APP_TOML}"
        fi
        if [ -n "${PRUNING_KEEP_RECENT:=}" ]; then
            sed -e "s|^pruning-keep-recent *=.*|pruning-keep-recent = \"${PRUNING_KEEP_RECENT}\"|" -i "${APP_TOML}"
        fi
        if [ -n "${PRUNING_INTERVAL:=}" ]; then
            sed -e "s|^pruning-interval *=.*|pruning-interval = \"${PRUNING_INTERVAL}\"|" -i "${APP_TOML}"
        fi
        if [ -n "${PRUNING_KEEP_EVERY:=}" ]; then
            sed -e "s|^pruning-keep-every *=.*|pruning-keep-every = \"${PRUNING_KEEP_EVERY}\"|" -i "${APP_TOML}"
        fi
        if [ -n "${MIN_RETAIN_BLOCKS:=}" ]; then
            sed -e "s|^min-retain-blocks *=.*|min-retain-blocks = \"${MIN_RETAIN_BLOCKS}\"|" -i "${APP_TOML}"
        fi
    fi

    if [ -n "${MINIMUM_GAS_PRICES:=}" ]; then
        sed -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"${MINIMUM_GAS_PRICES}\"|" -i "${APP_TOML}"
    fi

    if [ "${ENABLE_API:="true"}" = "true" ]; then
        sed -e '/^\[api\]/,/\[rosetta\]/ s|^enable *=.*|enable = true|' -i "${APP_TOML}"
    fi

    if [ "${ENABLE_GRPC:="true"}" = "true" ]; then
        sed -e '/^\[grpc\]/,/\[grpc-web\]/ s|^enable *=.*|enable = true|' -i "${APP_TOML}"
    fi

    if [ "${ENABLE_SWAGGER:="true"}" = "true" ]; then
        sed -e '/^\[api\]/,/\[rosetta\]/ s|^swagger *=.*|swagger = true|' -i "${APP_TOML}"
    fi

    if [ -n "${HALT_HEIGHT:=}" ]; then
        sed -e "s|^halt-height *=.*|halt-height = \"${HALT_HEIGHT}\"|" -i "${APP_TOML}"
    fi

    if [ -n "${MAX_RECV_MSG_SIZE:=}" ]; then
        sed -e "s|^max-recv-msg-size *=.*|max-recv-msg-size = \"${MAX_RECV_MSG_SIZE}\"|" -i "${APP_TOML}"
    fi
    chown cosmovisor:cosmovisor ${APP_TOML}*
}

# Call snapshot.py to load data from image
load_data_from_image() {
    if [[ ${RESTORE_SNAPSHOT:=} == "true" ]]; then
        snapshot.py "restore"
    elif [[ -n "${RESTORE_SNAPSHOT_URL:=}" ]]; then
        snapshot.py "restore" -u "${RESTORE_SNAPSHOT_URL}"
    fi
}

get_sync_block_height(){
    local latest_height
    local sync_block_height
    if [ -n "${STATE_SYNC_RPC:=}" ]; then
        latest_height=$(curl -sSL ${STATE_SYNC_RPC}/block | jq -r .result.block.header.height)
        if [ "${latest_height}" = "null" ]; then
            # Maybe Tendermint 0.35+?
            latest_height=$(curl -sSL ${STATE_SYNC_RPC}/block | jq -r .block.header.height)
        fi
        sync_block_height=$((${latest_height} - ${TRUST_LOOKBACK:=2000}))
    fi
    echo "${sync_block_height:=}"
}

get_sync_block_hash(){
    local sync_block_hash
    if [ -n "${STATE_SYNC_RPC:=}" ]; then
        sync_block_hash=$(curl -sSL "${STATE_SYNC_RPC}/block?height=${SYNC_BLOCK_HEIGHT}" | jq -r .result.block_id.hash)
        if [ "${sync_block_hash}" = "null" ]; then
            sync_block_hash=$(curl -sSL "${STATE_SYNC_RPC}/block?height=${SYNC_BLOCK_HEIGHT}" | jq -r .block_id.hash)
        fi
    fi
    echo "${sync_block_hash:=}"
}

prepare_statesync(){
    if [ -n "${WASM_URL:=}" ]; then
        logger "Downloading wasm files from ${WASM_URL}"
        wasm_base_dir=$(dirname ${WASM_DIR})
        mkdir -p "${wasm_base_dir}"
        curl -sSL "${WASM_URL}" | lz4 -c -d | tar -x -C "${wasm_base_dir}"
        chown -R cosmovisor:cosmovisor "${wasm_base_dir}"
    fi
}

# check to see if this file is being run or sourced from another script
_is_sourced() {
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
    prepare && start "$@"
fi
