#!/bin/bash

set -eu

if [ -n "${DEBUG:=}" ]; then
    set -x
fi

. /usr/local/bin/getchaininfo.sh

DAEMON_HOME=${DAEMON_HOME:="$(pwd)"}
CHAIN_JSON="${DAEMON_HOME}/chain.json"
UPGRADES_YML="${DAEMON_HOME}/upgrades.yml"

# Cosmovisor directory
COSMOVISOR_DIR="$(pwd)/cosmovisor"
CV_CURRENT_DIR="${COSMOVISOR_DIR}/current"
CV_GENESIS_DIR="${COSMOVISOR_DIR}/genesis"
CV_UPGRADES_DIR="${COSMOVISOR_DIR}/upgrades"

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

prepare_upgrade_json_version(){
    # If binary is defined in upgrade-info.json use it
    if [ -n "$(jq -r ".info | fromjson | .binaries.\"${ARCH}\"" ${UPGRADE_JSON})" ]; then
        logger "Using info from ${UPGRADE_JSON}..."
        create_cv_upgrade "$(cat ${UPGRADE_JSON})"
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
    logger "Found version ${upgrade_name}, Checking for ${upgrade_path}..."
    if [ "${binary_url}" != "null" ]; then
        mkdir -p "${upgrade_path}"
        download_cv_current "${binary_url}" "${binary_file}"
        link_cv_current "${upgrade_path}"
        if [ ${upgrade_height} -le 0 ]; then
            link_cv_genesis "${upgrade_path}"
        fi
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
    if [ -L "${CV_GENESIS_DIR}" ]; then
        logger "Removing existing ${CV_GENESIS_DIR}..."
        rm "${CV_GENESIS_DIR}"
    elif [ -e "${CV_GENESIS_DIR}" ]; then
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

    # Only download file if it does not already exist
    if [ ! -e "${binary_file}" ]; then
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
    fi
    chmod 0755 "${binary_file}"
    if [ "$(file -b ${binary_file})" = "JSON data" ]; then
        binary_url="$(jq -r ".binaries.\"${ARCH}\"" "${binary_file}")"
        download_cv_current "${binary_url}" "${binary_file}"
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

prepare_all_versions(){
    if [ ! -f "${UPGRADES_YML}" ]; then
        create_upgrades_yaml
    fi
    get_system_info 
    parse_upgrade_info
    download_binaries
}

# check to see if this file is being run or sourced from another script
_is_sourced() {
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

_main(){
    prepare_all_versions
    download_libraries
}

# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
	_main "$@"
fi
