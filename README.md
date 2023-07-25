# docker-cosmovisor

Docker Cosmovisor container designed to run any cosmoschain

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

## Example BINARY_INFO_URL file | [entrypoint.sh](https://github.com/terra-money/docker-cosmovisor/blob/0e325f19c89830fb3f7fc6ac3a95f73d8abddbd8/entrypoint.sh#L180)
```json
{
	"pisco-1": [{
		"name": "v2.0",
		"height": 1,
		"info": "{\"binaries\":{\"linux/amd64\":\"https://github.com/...\",\"darwin/amd64\":\"https://github.com/...\"}}"
	}],
	"uni-6": [{
		"name": "v12",
		"height": 23400,
		"info": "{\"binaries\":{\"linux/amd64\":\"https://github.com/CosmosContracts/juno/releases/download/v12.0.0/junod\"}}"
	}],
	"carbon-testnet-42069": [{
		"name": "v2.26.0",
		"height": 1944,
		"info": "{\"binaries\":{\"linux/amd64\":\"https://github.com/...\",\"darwin/amd64\":\"https://github.com/...\"}}"
	}]
}
```
