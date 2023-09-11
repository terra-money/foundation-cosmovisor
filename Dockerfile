ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="archlinux:base"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE} as cosmovisor

ARG COSMOVISOR_VERSION="v1.5.0"

RUN pacman -Syyu --noconfirm file jq yq lz4 curl unzip vim

COPY ./bin /usr/local/bin/

RUN set -eux && \
    curl -sSL https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2F${COSMOVISOR_VERSION}/cosmovisor-${COSMOVISOR_VERSION}-linux-amd64.tar.gz | \
    tar -xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/*

# Cosmosvisor vars
ENV DAEMON_HOME=/app \
    CHAIN_HOME=${CHAIN_HOME:-${DAEMON_HOME}} \
    DAEMON_ALLOW_DOWNLOAD_BINARIES=true \
    DAEMON_RESTART_AFTER_UPGRADE=true \
    UNSAFE_SKIP_BACKUP=true

# rest server
EXPOSE 1317
# grpc
EXPOSE 9090
# tendermint p2p
EXPOSE 26656
# tendermint rpc
EXPOSE 26657

RUN groupadd -g 1000 cosmovisor && \
    useradd -u 1000 -g 1000 -Md /app cosmovisor

USER cosmovisor
WORKDIR /app
VOLUME ["/app"]
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
CMD [ "cosmovisor", "run", "start", "--home", "${CHAIN_HOME}" ]

###############################################################################
FROM cosmovisor

ARG CHAIN_NAME="terra"
ARG CHAIN_NETWORK="mainnet"

ENV DAEMON_HOME=/app \
    CHAIN_HOME=${CHAIN_HOME:-${DAEMON_HOME}}

USER root

ENV CHAIN_NAME=${CHAIN_NAME} \
    CHAIN_NETWORK=${CHAIN_NETWORK}

COPY ./upgrades/${CHAIN_NAME}-${CHAIN_NETWORK}.yml /${DAEMON_HOME}/upgrades.yml

RUN set -eux && \
    export DEBUG=1 && \
    /usr/local/bin/getbinaries.sh

# Ensure CHAIN_HOME exists and is owned by cosmovisor
RUN mkdir -p ${CHAIN_HOME} && \
    chown -R cosmovisor:cosmovisor ${CHAIN_HOME}

#create dummy data folder to satisfy cosmovovisor
RUN mkdir -p ${DAEMON_HOME}/data

RUN chown -R cosmovisor:cosmovisor ${DAEMON_HOME}
USER cosmovisor