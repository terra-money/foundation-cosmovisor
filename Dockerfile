FROM alpine:3.16

RUN apk add --no-cache jq

WORKDIR /app

RUN wget -O- https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-amd64.tar.gz | \
    tar -xz -C /usr/local/bin


# Cosmosvisor vars
ENV DAEMON_HOME=/app \
    DAEMON_NAME=terrad \
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

COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/cosmovisor /usr/local/bin/entrypoint.sh

ENTRYPOINT [ "entrypoint.sh"]
CMD ["cosmovisor", "run", "start", "--home", "${DAEMON_HOME}"]