#!/bin/sh

set -eu

. $(dirname "$0")/entrypoint.sh

main(){
    if [ -f "${UPGRADES_YML}" ]; then
        get_system_info 
        parse_upgrade_info
        download_binaries
        download_libraries
    fi
}

parse_upgrade_info(){
    logger "Parsing upgrade information..."
    DAEMON_NAME="${DAEMON_NAME:=$(yq -r ".daemon_name" ${UPGRADES_YML})}"
    LIBRARY_URLS="${LIBRARY_URLS:=$(yq -r ".libraries[]" ${UPGRADES_YML})}"
}

download_binaries(){
    for tag in $(yq  ".versions[] | .tag"  ${UPGRADES_YML}); do
        binaries_content=$(yq -e ".versions[] | select(.tag == ${tag}) | .binaries" ${UPGRADES_YML})
        new_binaries_json="{\"binaries\":${binaries_content}}"
        binaries_json_encoded=$(echo "${new_binaries_json}" | jq '@json')        
        upgrade_info=$(yq -e ".versions[] | select(.tag == ${tag}) | {\"name\": .name, \"height\": (.height), \"info\": ${binaries_json_encoded}}" ${UPGRADES_YML})
        create_cv_upgrade "${upgrade_info}"
    done

    # we don't know the version at this point, let entrypoint identify the version to use
    if [ -L "${CV_CURRENT_DIR}" ]; then
        logger "Removing existing ${CV_CURRENT_DIR}..."
        rm "${CV_CURRENT_DIR}"
    elif [ -e "${CV_CURRENT_DIR}" ]; then
        logger "Removing existing ${CV_CURRENT_DIR}..."
        rm -rf "${CV_CURRENT_DIR}"
    fi
}

if [ "$(basename $0)" = "getbinaries.sh" ]; then
    main
fi