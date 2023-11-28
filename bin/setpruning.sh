#!/usr/bin/env bash

DAEMON_HOME=${DAEMON_HOME:="$(pwd)"}
CHAIN_HOME=${CHAIN_HOME:=$DAEMON_HOME}

# Config directory
CONFIG_DIR="${CHAIN_HOME}/config"
APP_TOML="${CONFIG_DIR}/app.toml"
CONFIG_TOML="${CONFIG_DIR}/config.toml"

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

set_pruning_main(){
    # Profile-based configuration
    local seconds_per_day=86400
    DAYS_TO_RETAIN=${DAYS_TO_RETAIN:=}
    MEAN_BLOCK_TIME=${MEAN_BLOCK_TIME:=6} # Mean block time in seconds
    UNBONDING_PERIOD=${UNBONDING_PERIOD:-$(parse_unbonding_period)}
    logger "Pruning profile set to ${PROFILE}"

    case "${PROFILE:-}" in
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
}

set_pruning_main

sed -e "s|^pruning *=.*|pruning = \"${PRUNING_STRATEGY}\"|" \
    -e "s|^pruning-keep-recent *=.*|pruning-keep-recent = \"${PRUNING_KEEP_RECENT}\"|" \
    -e "s|^pruning-interval *=.*|pruning-interval = \"${PRUNING_INTERVAL}\"|" \
    -e "s|^pruning-keep-every *=.*|pruning-keep-every = \"${PRUNING_KEEP_EVERY}\"|" \
    -e "s|^min-retain-blocks *=.*|min-retain-blocks = \"${MIN_RETAIN_BLOCKS}\"|" \
    -i "${APP_TOML}"

sed -e "s|^indexer *=.*|indexer = "\"${INDEXER}\""|" -i "${CONFIG_TOML}"