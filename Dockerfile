ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="binhex/arch-base"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE} as cosmovisor

ARG COSMOVISOR_VERSION="v1.5.0"

# Install dependencies
RUN pacman -Syyu --noconfirm file jq yq lz4 curl unzip

COPY ./bin /usr/local/bin/
COPY ./etc /etc/

RUN set -eux && \
    curl -sSL https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2F${COSMOVISOR_VERSION}/cosmovisor-${COSMOVISOR_VERSION}-linux-amd64.tar.gz | \
    tar -xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/*

# Cosmosvisor vars
ENV DAEMON_HOME=/app \
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
    useradd -u 1000 -g 1000 -s /bin/bash -Md /app cosmovisor 

WORKDIR /app
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
CMD [ "cosmovisor", "run", "start" ]

###############################################################################
FROM cosmovisor

ARG CHAIN_NAME="terra"
ARG CHAIN_NETWORK="mainnet"

ENV DAEMON_HOME=/app \
    CHAIN_NAME=${CHAIN_NAME} \
    CHAIN_NETWORK=${CHAIN_NETWORK}

COPY /upgrades/empty ./upgrades/${CHAIN_NAME}-${CHAIN_NETWORK}.yml* /tmp/

RUN set -eux && \
    export DEBUG=1 && \
    test ! -f /tmp/${CHAIN_NAME}-${CHAIN_NETWORK}.yml || mv /tmp/${CHAIN_NAME}-${CHAIN_NETWORK}.yml /app/upgrades.yml && \
    /usr/local/bin/getbinaries.sh && \
    chown -R cosmovisor:cosmovisor ${DAEMON_HOME}