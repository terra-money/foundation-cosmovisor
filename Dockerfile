FROM ubuntu:20.04

RUN apt update
RUN apt install -y curl vim sudo

RUN addgroup ubuntu \
    && adduser --ingroup ubuntu --disabled-login --home /home/ubuntu ubuntu
RUN echo "ubuntu  ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/ubuntu

#https://github.com/cosmos/cosmos-sdk/releases/tag/cosmovisor%2Fv1.3.0
RUN curl -L https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-amd64.tar.gz | tar xz && mv cosmovisor /usr/local/bin/cosmovisor

RUN mkdir /entrypoint
RUN mkdir /var/log/cosmovisor

RUN mkdir /app
RUN mkdir /app/data
RUN mkdir /app/config

COPY ./scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod u+x /usr/local/bin/cosmovisor /usr/local/bin/entrypoint.sh
RUN chown ubuntu:ubuntu /usr/local/bin/entrypoint.sh /usr/local/bin/cosmovisor /entrypoint /var/log/cosmovisor /app /app/*

USER ubuntu


# rest server
EXPOSE 1317
# grpc
EXPOSE 9090
# tendermint p2p
EXPOSE 26656
# tendermint rpc
EXPOSE 26657

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh"]