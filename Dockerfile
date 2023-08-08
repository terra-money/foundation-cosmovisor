ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="archlinux:base"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE}

RUN pacman -Syyu --noconfirm file jq lz4 curl

COPY ./bin /usr/local/bin/

RUN set -eux && \
    curl -sSL https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-amd64.tar.gz | \
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
    useradd -u 1000 -g 1000 -Md /app cosmovisor

USER cosmovisor
WORKDIR /app
VOLUME ["/app"]
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
CMD [ "cosmovisor", "run", "start", "--home", "/app" ]