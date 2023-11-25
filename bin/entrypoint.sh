#!/bin/bash

set -euo pipefail 

if [ -n "${DEBUG:=}" ]; then
    set -x
fi

DAEMON_HOME=${DAEMON_HOME:="$(pwd)"}
CHAIN_HOME=${CHAIN_HOME:=$DAEMON_HOME}
CHAIN_JSON="/etc/default/chain.json"
UPGRADES_JSON="/etc/default/upgrades.yml"

# Shared directory
SHARED_DIR=${SHARED:="${CHAIN_HOME}/shared"}
SNAPSHOTS_DIR="${SHARED_DIR}/snapshots"

# data directory
DATA_DIR="${CHAIN_HOME}/data"
WASM_DIR=${WASM_DIR:="${DATA_DIR}/wasm"}
UPGRADE_INFO_JSON="${DATA_DIR}/upgrade-info.json"

# Config directory
CONFIG_DIR="${CHAIN_HOME}/config"
APP_TOML="${CONFIG_DIR}/app.toml"
CLIENT_TOML="${CONFIG_DIR}/client.toml"
CONFIG_TOML="${CONFIG_DIR}/config.toml"
GENESIS_FILE="${CONFIG_DIR}/genesis.json"
NODE_KEY_FILE="${CONFIG_DIR}/node_key.json"
PV_KEY_FILE="${CONFIG_DIR}/priv_validator_key.json"
ADDR_BOOK_FILE="${CONFIG_DIR}/addrbook.json"


parse_chain_info(){
    if [ ! -f "${CHAIN_JSON}" ]; then
        getchaininfo.py
    fi
    logger "Parsing chain information..."
    export DAEMON_NAME=${DAEMON_NAME:="$(jq -r ".daemon_name" ${CHAIN_JSON})"}
    export CHAIN_ID=${CHAIN_ID:="$(jq -r ".chain_id" ${CHAIN_JSON})"}

    # Codebase Versions
    GENESIS_VERSION=${GENESIS_VERSION:="$(jq -r ".codebase.genesis.name" ${CHAIN_JSON})"}
    RECOMMENDED_VERSION=${RECOMMENDED_VERSION:="$(jq -r ".codebase.recommended_version" ${CHAIN_JSON})"}
    PREFER_RECOMMENDED_VERSION=${PREFER_RECOMMENDED_VERSION:=""}

    # app.toml
    CONTRACT_MEMORY_CACHE_SIZE=${CONTRACT_MEMORY_CACHE_SIZE:=8192}
    ENABLE_API=${ENABLE_API:=true}
    ENABLE_SWAGGER=${ENABLE_SWAGGER:=true}
    HALT_HEIGHT=${HALT_HEIGHT:=""}
    KEEP_SNAPSHOTS=${KEEP_SNAPSHOTS:=10}
    MONIKER=${MONIKER:="moniker"}
    MINIMUM_GAS_PRICES=${MINIMUM_GAS_PRICES:="$(jq -r '.fees.fee_tokens[] | [ .average_gas_price, .denom ] | join("")' ${CHAIN_JSON} | paste -sd, -)"}
    SNAPSHOT_INTERVAL=${SNAPSHOT_INTERVAL:=2000}     
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

logger(){
    echo "$*" | ts '[%Y-%m-%d %H:%M:%S]'
}

prepare(){
    parse_chain_info
    ensure_chain_home
    initialize_version
    initialize_node
    delete_data_dir
    load_data_from_image
    prepare_statesync
    set_node_key
    set_validator_key
    download_genesis
    download_addrbook
    set_pruning
    modify_client_toml
    modify_config_toml
    modify_app_toml
    chown -R cosmovisor:cosmovisor "${CHAIN_HOME}"
    chown -R cosmovisor:cosmovisor "${DAEMON_HOME}"
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
    if [ "${CHAIN_HOME}" != "${DAEMON_HOME}" ]; then
        ln -s ${CHAIN_HOME}/data ${DAEMON_HOME}/data;
    fi
}

initialize_version(){
    export DEBUG DAEMON_NAME DAEMON_HOME CHAIN_NAME \
    CHAIN_HOME CHAIN_JSON_URL BINARY_URL BINARY_VERSION 
    initversion.py
    if [ $? != 0 ]; then
        exit $?
    fi
}

# Initialize the node
initialize_node(){
    # TODO: initialize in tmpdir and copy any missing files to the config dir
    if [ ! -d "${CONFIG_DIR}" ] || [ ! -f "${GENESIS_FILE}" ]; then
        logger "Initializing node from scratch..."
        mkdir -p "${DATA_DIR}"
        /usr/local/bin/cosmovisor run init "${MONIKER}" --home "${CHAIN_HOME}" --chain-id "${CHAIN_ID}"
        if [ -f "${GENESIS_FILE}" ]; then
            rm "${GENESIS_FILE}"
        else
            echo "Failed to initialize node." >&2
            exit $?
        fi
    fi
}

delete_data_dir(){
    if [ "${RESET_ON_START}" = "true" ]; then
        logger "Reset on start set to: ${RESET_ON_START}"
        cp "${DATA_DIR}/priv_validator_state.json" /tmp/priv_validator_state.json.backup
        rm -rf "${DATA_DIR}"
        mkdir -p "${DATA_DIR}"
        mv /tmp/priv_validator_state.json.backup "${DATA_DIR}/priv_validator_state.json"
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
set_validator_key(){
    if [ -n "${PRIVATE_VALIDATOR_KEY}" ]; then
        echo "Using private key from env..."
        echo "${PRIVATE_VALIDATOR_KEY}" | base64 -d > "${PV_KEY_FILE}"
    fi
}

# Retrieve the genesis file
download_genesis(){
    if [ ! -d "${CONFIG_DIR}" ]; then
        mkdir -p "${CONFIG_DIR}"
    fi

    if [ ! -f "${GENESIS_FILE}" ] && [ -n "${GENESIS_URL}" ]; then
        logger "Downloading genesis file from ${GENESIS_URL}..."
        case "${GENESIS_URL}" in
            *.tar.gz)
                curl -sSL "${GENESIS_URL}" | tar -xz -C "${CONFIG_DIR}" 2>/dev/null
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

calculate_min_retain_blocks() {
    local unbonding_period_seconds="$1" # Unbonding time in seconds
    local block_time_seconds="${MEAN_BLOCK_TIME}" # Use the MEAN_BLOCK_TIME variable

    # Calculate the number of blocks for the unbonding period
    local unbonding_blocks=$((unbonding_period_seconds / block_time_seconds))

    # Initialize days_blocks to 0
    local days_blocks=0

    # Calculate the number of blocks for the specified days, only if DAYS_TO_RETAIN is defined and greater than 0
    if [ -n "${DAYS_TO_RETAIN}" ] && [ "${DAYS_TO_RETAIN}" -gt 0 ]; then
        days_blocks=$((DAYS_TO_RETAIN * 86400 / block_time_seconds)) # 86400 seconds per day
    fi

    # Choose the larger value between unbonding blocks and days blocks
    local max_blocks=$(( unbonding_blocks > days_blocks ? unbonding_blocks : days_blocks ))
    
    # Set safety_margin to 25% of max_blocks
    local safety_margin=$((max_blocks / 4))
    
    # Add a safety margin
    echo $((max_blocks + safety_margin))
}


parse_unbonding_period() {
    local genesis_file="${CONFIG_DIR}/genesis.json"
    local unbonding_time_str=$(jq -r '.app_state.staking.params.unbonding_time' "${genesis_file}")

    # Default unbonding time in seconds
    local unbonding_time_seconds=0

    # Extract the number and the unit (s, h, d)
    local number=$(echo "${unbonding_time_str}" | grep -o -E '[0-9]+')
    local unit=$(echo "${unbonding_time_str}" | grep -o -E '[a-z]+')

    case "${unit}" in
        s)
            unbonding_time_seconds=${number}
            ;;
        m)
            unbonding_time_seconds=$((number * 60)) # Convert minutes to seconds
            ;;
        h)
            unbonding_time_seconds=$((number * 3600)) # Convert hours to seconds
            ;;
        d)
            unbonding_time_seconds=$((number * 86400)) # Convert days to seconds
            ;;
        *)
            echo "Unknown time unit in unbonding_time"
            exit 1
            ;;
    esac

    # Return the unbonding time in seconds only if it is greater than 0
    if [ "${unbonding_time_seconds}" -gt 0 ]; then
        echo "${unbonding_time_seconds}"
    fi
}

set_pruning(){
    # Profile-based configuration
    if [ -n "${PROFILE:=}" ]; then
        local seconds_per_day=86400
        DAYS_TO_RETAIN=${DAYS_TO_RETAIN:=}
        MEAN_BLOCK_TIME=${MEAN_BLOCK_TIME:=6} # Mean block time in seconds
        UNBONDING_PERIOD=${UNBONDING_PERIOD:-$(parse_unbonding_period)}
        logger "Pruning profile set to ${PROFILE}"
        case "${PROFILE}" in
            read)
                if [ -z "${UNBONDING_PERIOD}" ]; then
                    echo "Error: UNBONDING_PERIOD must be defined for ${PROFILE} profile."
                    exit 1
                fi
                # For read profile, want to be able to set the retention in days, default is 30
                DAYS_TO_RETAIN=${DAYS_TO_RETAIN:=30}
                # Set variables for read profile
                PRUNING_INTERVAL=${PRUNING_INTERVAL:=10}
                PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:=$((DAYS_TO_RETAIN * seconds_per_day / MEAN_BLOCK_TIME))}             
                PRUNING_KEEP_EVERY=${PRUNING_KEEP_EVERY:=${SNAPSHOT_INTERVAL}}
                PRUNING_STRATEGY=${PRUNING_STRATEGY:="custom"}
                MIN_RETAIN_BLOCKS=${MIN_RETAIN_BLOCKS:=$(calculate_min_retain_blocks "${UNBONDING_PERIOD}" "${DAYS_TO_RETAIN}")}                                
                INDEXER="null"
                ;;
            write)
                if [ -z "${UNBONDING_PERIOD}" ]; then
                    echo "Error: UNBONDING_PERIOD must be defined for ${PROFILE} profile."
                    exit 1
                fi            
                # Set variables for write profile
                PRUNING_INTERVAL=${PRUNING_INTERVAL:=10}
                PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:=100}
                PRUNING_KEEP_EVERY=${PRUNING_KEEP_EVERY:="${SNAPSHOT_INTERVAL}"}
                PRUNING_STRATEGY=${PRUNING_STRATEGY:="custom"}
                MIN_RETAIN_BLOCKS=${MIN_RETAIN_BLOCKS:=$(calculate_min_retain_blocks "${UNBONDING_PERIOD}")}
                INDEXER="null"
                ;;
            snap)
                if [ -z "${UNBONDING_PERIOD}" ]; then
                    echo "Error: UNBONDING_PERIOD must be defined for ${PROFILE} profile."
                    exit 1
                fi
                # For read profile, want to be able to set the retention in days, default is 30
                DAYS_TO_RETAIN=${DAYS_TO_RETAIN:=30}
                # Set variables for read profile
                PRUNING_INTERVAL=${PRUNING_INTERVAL:=10}
                PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:=$((DAYS_TO_RETAIN * seconds_per_day / MEAN_BLOCK_TIME))}             
                PRUNING_KEEP_EVERY=${PRUNING_KEEP_EVERY:=${SNAPSHOT_INTERVAL}}
                PRUNING_STRATEGY=${PRUNING_STRATEGY:="custom"}
                MIN_RETAIN_BLOCKS=${MIN_RETAIN_BLOCKS:=$(calculate_min_retain_blocks "${UNBONDING_PERIOD}" "${DAYS_TO_RETAIN}")}                                
                INDEXER="null"
                COSMPRUND_ENABLED=${COSMPRUND_ENABLED:="true"}
                LZ4_SNAPSHOT_ENABLED=${LZ4_SNAPSHOT_ENABLED:="true"}
                ;;
            archive)
                # Set variables for archive profile
                PRUNING_INTERVAL=${PRUNING_INTERVAL:=0}
                PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:=0}
                PRUNING_KEEP_EVERY=${PRUNING_KEEP_EVERY:=0}
                PRUNING_STRATEGY=${PRUNING_STRATEGY:="nothing"}
                MIN_RETAIN_BLOCKS=${MIN_RETAIN_BLOCKS:=0}
                INDEXER="kv"
                ;;
            *)
                logger "Unknown profile: ${PROFILE}, setting default pruning settings"
                set_default_pruning
                ;;
        esac
    else
        set_default_pruning
    fi
    if [ ${LZ4_SNAPSHOT_ENABLED:=} = "true" ]; then
        sed -e "s|^autostart=false|autostart=true|" -i /etc/supervisor.d/snapshot.conf
    fi
}

set_default_pruning() {
    logger "Setting default pruning settings"
    #If profile is not set, use the defaults
    PRUNING_INTERVAL=${PRUNING_INTERVAL:=10}
    PRUNING_KEEP_RECENT=${PRUNING_KEEP_RECENT:=100}
    PRUNING_KEEP_EVERY=${PRUNING_KEEP_EVERY:=0}
    # choosing nothing as the default pruning strategy / 0 as min retain blocks
    # to avoid accidentally pruning data on an archival node
    PRUNING_STRATEGY=${PRUNING_STRATEGY:="nothing"}
    MIN_RETAIN_BLOCKS=${MIN_RETAIN_BLOCKS:=0}    
    COSMPRUND_ENABLED=${COSMPRUND_ENABLED:="false"}
    LZ4_SNAPSHOT_ENABLED=${LZ4_SNAPSHOT_ENABLED:="false"}
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

    if [ -n "${RPC_CORS_ALLOWED_ORIGIN:-}" ]; then
        sed -e "s|^cors.allowed.origins *=.*|cors_allowed_origins = ${RPC_CORS_ALLOWED_ORIGIN}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${NODE_MODE}" ]; then
        sed -e "s|^mode *=.*|mode = \"${NODE_MODE}\"|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${MAX_BODY_BYTES:-}" ]; then
        sed -e "s|^max.body.bytes *=.*|max_body_bytes = ${MAX_BODY_BYTES}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${MAX_HEADER_BYTES:-}" ]; then
        sed -e "s|^max.header.bytes *=.*|max_header_bytes = ${MAX_HEADER_BYTES}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${MAX_PAYLOAD:-}" ]; then
        sed -e "s|^max.packet.msg.payload.size *=.*|max_packet_msg_payload_size = ${MAX_PAYLOAD}|" -i "${CONFIG_TOML}"
    fi

    if [ -n "${INDEXER:-}" ]; then
        sed -e "s|^indexer *=.*|indexer = "\"${INDEXER}\""|" -i "${CONFIG_TOML}"
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

    if [ -n "${TIMEOUT_COMMIT}" ]; then
        sed -e "s|^timeout.commit *=.*|timeout_commit = \"${TIMEOUT_COMMIT}\"|" -i "${CONFIG_TOML}"
    fi
}

modify_app_toml(){
    cp "${APP_TOML}" "${APP_TOML}.bak"
    sed -e "s|^moniker *=.*|moniker = \"${MONIKER}\"|" -i "${APP_TOML}"
    sed -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"${MINIMUM_GAS_PRICES}\"|" -i "${APP_TOML}"
    sed -e "s|^pruning *=.*|pruning = \"${PRUNING_STRATEGY}\"|" -i "${APP_TOML}"
    sed -e "s|^pruning-keep-recent *=.*|pruning-keep-recent = \"${PRUNING_KEEP_RECENT}\"|" -i "${APP_TOML}"
    sed -e "s|^pruning-interval *=.*|pruning-interval = \"${PRUNING_INTERVAL}\"|" -i "${APP_TOML}"
    sed -e "s|^pruning-keep-every *=.*|pruning-keep-every = \"${PRUNING_KEEP_EVERY}\"|" -i "${APP_TOML}"
    sed -e "s|^min-retain-blocks *=.*|min-retain-blocks = \"${MIN_RETAIN_BLOCKS}\"|" -i "${APP_TOML}"
    sed -e "s|^snapshot-interval *=.*|snapshot-interval = \"${SNAPSHOT_INTERVAL}\"|" -i "${APP_TOML}"
    sed -e "s|^snapshot-keep-recent *=.*|snapshot-keep-recent = \"${KEEP_SNAPSHOTS}\"|" -i "${APP_TOML}"
    sed -e "s|^contract-memory-cache-size *=.*|contract-memory-cache-size = \"${CONTRACT_MEMORY_CACHE_SIZE}\"|" -i "${APP_TOML}"
    sed -e "s|^rpc-max-body-bytes *=.*|rpialize_c-max-body-bytes = \"${RPC_MAX_BODY_BYTES}\"|" -i "${APP_TOML}"

    sed -e "s|^address *=.*:1317.*$|address = \"tcp:\/\/0.0.0.0:1317\"|" \
        -e "s|^address *=.*:8080.*$|address = \"0.0.0.0:8080\"|" \
        -e "s|^address *=.*:9090.*$|address = \"0.0.0.0:9090\"|" \
        -e "s|^address *=.*:9091.*$|address = \"0.0.0.0:9091\"|" \
        -i "${APP_TOML}"

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

# Call snapshot.py to load data from image
load_data_from_image() {
    if [[ ${RESTORE_SNAPSHOT:="false"} == "true" ]]; then
        snapshot.py "restore"
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

prepare_statesync(){
    if [ -n "${WASM_URL}" ]; then
        logger "Downloading wasm files from ${WASM_URL}"
        wasm_base_dir=$(dirname ${WASM_DIR})
        mkdir -p "${wasm_base_dir}"
        curl -sSL "${WASM_URL}" | lz4 -c -d | tar -x -C "${wasm_base_dir}"
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
