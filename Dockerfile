ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="binhex/arch-base"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE} as cosmovisor

ARG COSMOVISOR_VERSION="v1.5.0"

# Install dependencies
#RUN pacman -Syyu --noconfirm curl file jq lz4 unzip
RUN pacman -Syyu --noconfirm \
    aria2 \
    musl \
    python-lz4 \
    python-pip \
    python-yaml \
    python-tomlkit \
    python-requests \
    python-dnspython \
    skopeo \
    tmux \
    vim \
    wget

# install grpcurl and cosmovisor
RUN set -eux && \
    curl -sSL https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2F${COSMOVISOR_VERSION}/cosmovisor-${COSMOVISOR_VERSION}-linux-amd64.tar.gz | \
    tar -xz -C /usr/local/bin cosmovisor && \
    rm /usr/lib/python3.11/EXTERNALLY-MANAGED 

COPY --from=ghcr.io/binaryholdings/cosmprund:v1.0.0 /usr/bin/cosmprund /usr/local/bin/cosmprund
COPY ./etc /etc/
COPY ./bin/* /usr/local/bin/

# set permissions and create user
RUN set -eux && \
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
ARG CHAIN_DIR

ENV CHAIN_NAME=${CHAIN_NAME} \
    LD_LIBRARY_PATH=/app/cosmovisor/current/lib

COPY ./chains/${CHAIN_DIR}/* /etc/default/

# install binaries to /opt/cosmovisor
RUN set -eux && \
    /usr/local/bin/getupgrades.py -d /opt/cosmovisor 