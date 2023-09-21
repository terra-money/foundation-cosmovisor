ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="binhex/arch-base"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE} as cosmovisor

ARG COSMOVISOR_VERSION="v1.5.0"

# Install dependencies
#RUN pacman -Syyu --noconfirm curl file jq lz4 unzip
RUN pacman -Syyu --noconfirm python-pip python-requests python-yaml skopeo

COPY ./etc /etc/
COPY ./bin/* /usr/local/bin/

RUN set -eux && \
    curl -sSL https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2F${COSMOVISOR_VERSION}/cosmovisor-${COSMOVISOR_VERSION}-linux-amd64.tar.gz | \
    tar -xz -C /usr/local/bin && \
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
CMD [ "cosmovisor", "run", "start", "--home", "${CHAIN_HOME}" ]

###############################################################################
FROM cosmovisor

ARG CHAIN_NAME="terra"
ARG CHAIN_NETWORK="mainnet"

ENV CHAIN_NAME=${CHAIN_NAME} \
    CHAIN_NETWORK=${CHAIN_NETWORK}

COPY /upgrades/empty ./upgrades/${CHAIN_NAME}-${CHAIN_NETWORK}.yml* /tmp/

RUN set -eux && \
    if [ -f /tmp/${CHAIN_NAME}-${CHAIN_NETWORK}.yml ]; then \
    mv /tmp/${CHAIN_NAME}-${CHAIN_NETWORK}.yml /app/upgrades.yml; \
    fi && \ 
    /usr/local/bin/getupgrades.py && \
    chown -R cosmovisor:cosmovisor ${DAEMON_HOME}
