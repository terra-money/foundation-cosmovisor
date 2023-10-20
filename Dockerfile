ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="binhex/arch-base"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE} as cosmovisor

ARG COSMOVISOR_VERSION="v1.5.0"

# Install dependencies
#RUN pacman -Syyu --noconfirm curl file jq lz4 unzip
RUN pacman -Syyu --noconfirm \
    aria2 \
    python-pip \
    python-requests \
    python-yaml \
    skopeo \
    wget

COPY ./etc /etc/
COPY ./bin/* /usr/local/bin/

# install grpcurl and cosmovisor
RUN set -eux && \
    curl -sSL https://github.com/fullstorydev/grpcurl/releases/download/v1.8.8/grpcurl_1.8.8_linux_$(uname -m).tar.gz | \
    tar -xz -C /usr/local/bin/ grpcurl && \
    curl -sSL https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2F${COSMOVISOR_VERSION}/cosmovisor-${COSMOVISOR_VERSION}-linux-amd64.tar.gz | \
    tar -xz -C /usr/local/bin cosmovisor && \
    chmod +x /usr/local/bin/* && \
    groupadd -g 1000 cosmovisor && \
    useradd -u 1000 -g 1000 -s /bin/bash -Md /app cosmovisor 

# Cosmosvisor vars
ENV HOME=/app \
    CHAIN_HOME=/app \
    DAEMON_HOME=/app \
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

WORKDIR /app
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
CMD [ "cosmovisor", "run", "start", "--home", "/app" ]

###############################################################################
FROM cosmovisor as final

ARG CHAIN_NAME
ARG CHAIN_NETWORK

ENV CHAIN_NAME=${CHAIN_NAME} \
    CHAIN_NETWORK=${CHAIN_NETWORK}

COPY ./chains/${CHAIN_NAME}-${CHAIN_NETWORK}/* /etc/default/

RUN set -eux && \
    mkdir -p /app/cosmovisor && \
    mkdir -p /opt/cosmovisor/upgrades && \
    ln -s /opt/cosmovisor/upgrades /app/cosmovisor/upgrades && \
    ln -s /opt/cosmovisor/genesis /app/cosmovisor/genesis && \
    /usr/local/bin/getupgrades.py && \
    chown -R cosmovisor:cosmovisor /opt/cosmovisor/upgrades