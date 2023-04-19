# docker-cosmovisor

Docker Comovisor container designed to run any comsoschain

## Examples ()

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

## Acknowlegdments

- entrypoint script modeled from: []
