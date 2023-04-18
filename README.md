# docker-cosmovisor

## Examples

- terra pisco-1 testnet from genesis
```sh
    docker run --platform=linux/amd64 --rm -it \
        -e CHAIN_JSON_URL="https://raw.githubusercontent.com/cosmos/chain-registry/master/testnets/terra2testnet/chain.json" \
        test:latest
```

- terra pisco-1 testnet statesync
```sh
    docker run --platform=linux/amd64 --rm -it \
        -e CHAIN_JSON_URL="https://raw.githubusercontent.com/cosmos/chain-registry/master/testnets/terra2testnet/chain.json" \
        -e STATE_SYNC_RPC="https://terra-rpc.polkachu.com:443" \
        -e WASM_URL="https://snapshots.polkachu.com/testnet-wasm/terra/wasmonly.tar.lz4" \
        test:latest
```
