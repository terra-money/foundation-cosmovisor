#!/bin/sh

set -eux

BINPATH=$(dirname "$0")
UPGRADES_YML="/app/config/upgrades.yml"

. ${BINPATH}/entrypoint.sh

if [ -f "${UPGRADES_YML}" ]; then
    for tag in $(yq  ".[] | .tag"  ${UPGRADES_YML}); do
        upgrade_info=$(yq  -o json ".[] | select(.tag == \"${tag}\") | {\"name\": .name, \"height\": (.height // 0), \"info\": ({\"binaries\": .binaries} | tostring)}" ${UPGRADES_YML})
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
