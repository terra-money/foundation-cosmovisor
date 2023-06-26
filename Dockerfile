ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="archlinux:base"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE}

RUN pacman -Syyu --noconfirm file jq lz4 curl supervisor

COPY ./entrypoint.sh scripts/health_check.sh scripts/unjail_watcher.sh /usr/local/bin/

RUN curl -sSL https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-amd64.tar.gz | \
    tar -xz -C /usr/local/bin

RUN chmod +x /usr/local/bin/cosmovisor /usr/local/bin/entrypoint.sh /usr/local/bin/health_check.sh /usr/local/bin/unjail_watcher.sh

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

WORKDIR /app

RUN groupadd -g 1000 cosmovisor # && \
    useradd -u 1000 -g 1000 -Mh /app cosmovisor

#USER cosmovisor
# Copy supervisord configuration file
COPY supervisord.conf /etc/supervisord.conf

VOLUME ["/app"]

# Set supervisord as the entrypoint
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]