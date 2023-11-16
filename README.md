# docker-cosmovisor

Docker Cosmovisor container to run any cosmoschain

## Chain specific build examples

```sh
 docker compose --env-file chains/akash-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/akash-testnet/.env up --build --force-recreate
 docker compose --env-file chains/archway-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/archway-testnet/.env up --build --force-recreate
 docker compose --env-file chains/axelar-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/axelar-testnet/.env up --build --force-recreate
 docker compose --env-file chains/carbon-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/carbon-testnet/.env up --build --force-recreate
 docker compose --env-file chains/celestia-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/celestia-testnet/.env up --build --force-recreate
 docker compose --env-file chains/cheqd-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/cheqd-testnet/.env up --build --force-recreate
 docker compose --env-file chains/chihuahua-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/chihuahua-testnet/.env up --build --force-recreate
 docker compose --env-file chains/cosmoshub-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/cosmoshub-testnet/.env up --build --force-recreate
 docker compose --env-file chains/crescent-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/crescent-testnet/.env up --build --force-recreate
 docker compose --env-file chains/decentr-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/decentr-testnet/.env up --build --force-recreate
 docker compose --env-file chains/dydx-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/injective-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/injective-testnet/.env up --build --force-recreate
 docker compose --env-file chains/juno-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/juno-testnet/.env up --build --force-recreate
 docker compose --env-file chains/kava-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/kava-testnet/.env up --build --force-recreate
 docker compose --env-file chains/kujira-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/kujira-testnet/.env up --build --force-recreate
 docker compose --env-file chains/mars-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/mars-testnet/.env up --build --force-recreate
 docker compose --env-file chains/migaloo-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/migaloo-testnet/.env up --build --force-recreate
 docker compose --env-file chains/neutron-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/neutron-testnet/.env up --build --force-recreate
 docker compose --env-file chains/noble-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/noble-testnet/.env up --build --force-recreate
 docker compose --env-file chains/osmosis-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/osmosis-testnet/.env up --build --force-recreate
 docker compose --env-file chains/sei-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/sei-testnet/.env up --build --force-recreate
 docker compose --env-file chains/terra-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/terra-testnet/.env up --build --force-recreate
 docker compose --env-file chains/terraclassic-mainnet/.env up --build --force-recreate
 docker compose --env-file chains/terraclassic-testnet/.env up --build --force-recreate
```

## Base container examples

### Terra pisco-1 testnet from genesis

```sh
    docker run --platform=linux/amd64 --rm -it \
        -e CHAIN_JSON_URL="https://raw.githubusercontent.com/cosmos/chain-registry/master/testnets/terra2testnet/chain.json" \
        ghcr.io/terra-money/docker-cosmovisor:latest
```

### Terra pisco-1 testnet from statesync

```sh
    docker run --platform=linux/amd64 --rm -it \
        -e CHAIN_JSON_URL="https://raw.githubusercontent.com/cosmos/chain-registry/master/testnets/terra2testnet/chain.json" \
        -e STATE_SYNC_RPC="https://terra-testnet-rpc.polkachu.com:443" \
        -e WASM_URL="https://snapshots.polkachu.com/testnet-wasm/terra/wasmonly.tar.lz4" \
        ghcr.io/terra-money/docker-cosmovisor:latest
```

### Terra phoenix-1 mainnet from genesis

```sh
    docker run --platform=linux/amd64 --rm -it \
        -e CHAIN_JSON_URL="https://raw.githubusercontent.com/cosmos/chain-registry/master/terra2/chain.json" \
        ghcr.io/terra-money/docker-cosmovisor:latest
```

### Terra phoenix-1 testnet from statesync

```sh
    docker run --platform=linux/amd64 --rm -it \
        -e CHAIN_JSON_URL="https://raw.githubusercontent.com/cosmos/chain-registry/master/terra2/chain.json" \
        -e STATE_SYNC_RPC="https://terra-rpc.polkachu.com:443" \
        -e WASM_URL="https://snapshots.polkachu.com/wasm/terra/wasmonly.tar.lz4" \
        ghcr.io/terra-money/docker-cosmovisor:latest
```

### Terra classic columbus from genesis

```sh
    docker run --platform=linux/amd64 --rm -it \
        -e CHAIN_JSON_URL="https://raw.githubusercontent.com/cosmos/chain-registry/master/terra/chain.json" \
        ghcr.io/terra-money/docker-cosmovisor:latest
```
