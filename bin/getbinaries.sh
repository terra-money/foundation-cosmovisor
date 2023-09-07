#!/bin/sh

set -eux

BINPATH=$(dirname "$0")
DAEMON_NAME=${DAEMON_NAME:="appd"}

. ${BINPATH}/entrypoint.sh

get_system_info 
mkdir -p ${CV_UPGRADES_DIR}

if [ -f "${UPGRADES_YML}" ]; then
    for tag in $(yq  ".[] | .tag"  ${UPGRADES_YML}); do
        binaries_content=$(yq -e ".[] | select(.tag == ${tag}) | .binaries" ${UPGRADES_YML})
        new_binaries_json="{\"binaries\":${binaries_content}}"
        binaries_json_encoded=$(echo "${new_binaries_json}" | jq '@json')        
        upgrade_info=$(yq -e ".[] | select(.tag == ${tag}) | {\"name\": .name, \"height\": (.height // 0), \"info\": ${binaries_json_encoded}}" ${UPGRADES_YML})
        create_cv_upgrade "${upgrade_info}"
    done
    if [ -L "${CV_CURRENT_DIR}" ]; then
        logger "Removing existing ${CV_CURRENT_DIR}..."
        rm "${CV_CURRENT_DIR}"
    elif [ -e "${CV_CURRENT_DIR}" ]; then
        logger "Removing existing ${CV_CURRENT_DIR}..."
        rm -rf "${CV_CURRENT_DIR}"
    fi
fi
