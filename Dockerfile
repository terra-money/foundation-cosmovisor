ARG ALPINE_VERSION="3.16"
ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="alpine:${ALPINE_VERSION}"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE}

RUN apk add --no-cache jq

COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /app

RUN wget -O- https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-amd64.tar.gz | \
    tar -xz -C /usr/local/bin

RUN chmod +x /usr/local/bin/cosmovisor /usr/local/bin/entrypoint.sh

# Chain registry name
ENV CHAIN_REGISTRY_NAME=terra2testnet

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

RUN addgroup -g 1000 cosmovisor && \
    adduser -u 1000 -G cosmovisor -D -h /app cosmovisor

ENTRYPOINT [ "entrypoint.sh"]
CMD ["cosmovisor", "run", "start", "--home", "./"]