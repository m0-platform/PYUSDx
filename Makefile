# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# dapp deps
update:; forge update

# Uses the 1Password CLI to inject secrets referenced in .env into the forge process.
# In .env, set secret values as 1Password references, e.g. PRIVATE_KEY="op://vault/item/field".
# `op run` injects every .env var, so the scripts read them (PRIVATE_KEY, PYUSDX_*, etc.) directly via vm.env*.
OP_RUN := op run --env-file=".env" --

# Deployment helpers
# CHAIN selects the foundry rpc_endpoints alias (localhost/mainnet/arbitrum/sepolia), resolved from
# the matching *_RPC_URL env var that `op run` injects.
# The non-secret config vars are listed explicitly so it's clear which env vars the deploy consumes;
# PRIVATE_KEY (and the RPC URL) are the only secrets and are injected by `op run`.
deploy:
	PYUSDX_NAME=$(PYUSDX_NAME) PYUSDX_SYMBOL=$(PYUSDX_SYMBOL) \
	PYUSDX_ADMIN=$(PYUSDX_ADMIN) PYUSDX_PAUSER=$(PYUSDX_PAUSER) \
	PYUSDX_FREEZE_MANAGER=$(PYUSDX_FREEZE_MANAGER) PYUSDX_FORCED_TRANSFER_MANAGER=$(PYUSDX_FORCED_TRANSFER_MANAGER) \
	PYUSDX_EARNER_MANAGER=$(PYUSDX_EARNER_MANAGER) PYUSDX_RATE_MANAGER=$(PYUSDX_RATE_MANAGER) \
	PYUSDX_EARNER_MANAGER_RATE_LIMIT_CAPACITY=$(PYUSDX_EARNER_MANAGER_RATE_LIMIT_CAPACITY) \
	PYUSDX_EARNER_MANAGER_RATE_LIMIT_REFILL=$(PYUSDX_EARNER_MANAGER_RATE_LIMIT_REFILL) \
	ISSUER_GATEWAY_ADMIN=$(ISSUER_GATEWAY_ADMIN) ISSUER_GATEWAY_OPERATOR=$(ISSUER_GATEWAY_OPERATOR) \
	ISSUER_GATEWAY_EXECUTOR=$(ISSUER_GATEWAY_EXECUTOR) ISSUER_GATEWAY_MINT_DELAY=$(ISSUER_GATEWAY_MINT_DELAY) \
	ISSUER_GATEWAY_MINT_TTL=$(ISSUER_GATEWAY_MINT_TTL) \
	ISSUER_GATEWAY_RATE_LIMIT_CAPACITY=$(ISSUER_GATEWAY_RATE_LIMIT_CAPACITY) \
	ISSUER_GATEWAY_RATE_LIMIT_REFILL=$(ISSUER_GATEWAY_RATE_LIMIT_REFILL) \
	SWAP_FACILITY_ADMIN=$(SWAP_FACILITY_ADMIN) SWAP_FACILITY_PAUSER=$(SWAP_FACILITY_PAUSER) \
	FACTORY_ADMIN=$(FACTORY_ADMIN) FACTORY_MANAGER=$(FACTORY_MANAGER) \
	PORTAL_ADMIN=$(PORTAL_ADMIN) PORTAL_PAUSER=$(PORTAL_PAUSER) PORTAL_OPERATOR=$(PORTAL_OPERATOR) \
	PORTAL_FALLBACK_RECIPIENT=$(PORTAL_FALLBACK_RECIPIENT) \
	PORTAL_RATE_LIMIT_CAPACITY=$(PORTAL_RATE_LIMIT_CAPACITY) PORTAL_RATE_LIMIT_REFILL=$(PORTAL_RATE_LIMIT_REFILL) \
	LAYER_ZERO_ENDPOINT=$(LAYER_ZERO_ENDPOINT) \
	LAYER_ZERO_BRIDGE_ADAPTER_ADMIN=$(LAYER_ZERO_BRIDGE_ADAPTER_ADMIN) \
	LAYER_ZERO_BRIDGE_ADAPTER_OPERATOR=$(LAYER_ZERO_BRIDGE_ADAPTER_OPERATOR) \
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/deploy/DeployAll.s.sol:DeployAll \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive --broadcast --verify

deploy-local: CHAIN=localhost
deploy-local: deploy

deploy-mainnet: CHAIN=mainnet
deploy-mainnet: deploy

deploy-arbitrum: CHAIN=arbitrum
deploy-arbitrum: deploy

deploy-sepolia: CHAIN=sepolia
deploy-sepolia: deploy

deploy-arbitrum-sepolia: CHAIN=arbitrum-sepolia
deploy-arbitrum-sepolia: deploy

# Portal configuration helpers
# PEERS is a Solidity uint32[] literal of remote chain IDs. It defaults to an empty array and is set
# by the per-network targets below; override on the CLI with PEERS='[...]'.
PEERS ?= []

configure-portal:
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/configure/ConfigurePortal.s.sol:ConfigurePortal \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive --broadcast

configure-portal-local: PEERS = [42161]
configure-portal-local: CHAIN=localhost
configure-portal-local: configure-portal

configure-portal-mainnet: PEERS = [42161]
configure-portal-mainnet: CHAIN=mainnet
configure-portal-mainnet: configure-portal

configure-portal-arbitrum: PEERS = [1]
configure-portal-arbitrum: CHAIN=arbitrum
configure-portal-arbitrum: configure-portal

configure-portal-sepolia: PEERS = [421614]
configure-portal-sepolia: CHAIN=sepolia
configure-portal-sepolia: configure-portal

configure-portal-arbitrum-sepolia: PEERS = [11155111]
configure-portal-arbitrum-sepolia: CHAIN=arbitrum-sepolia
configure-portal-arbitrum-sepolia: configure-portal

# LayerZero ULN/DVN security config. Signer must be the adapter's LayerZero delegate.
configure-lz-adapter:
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/configure/ConfigureLayerZero.s.sol:ConfigureLayerZero \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive --broadcast

configure-lz-adapter-local: PEERS = [42161]
configure-lz-adapter-local: CHAIN=localhost
configure-lz-adapter-local: configure-lz-adapter

configure-lz-adapter-mainnet: PEERS = [42161]
configure-lz-adapter-mainnet: CHAIN=mainnet
configure-lz-adapter-mainnet: configure-lz-adapter

configure-lz-adapter-arbitrum: PEERS = [1]
configure-lz-adapter-arbitrum: CHAIN=arbitrum
configure-lz-adapter-arbitrum: configure-lz-adapter

configure-lz-adapter-sepolia: PEERS = [421614]
configure-lz-adapter-sepolia: CHAIN=sepolia
configure-lz-adapter-sepolia: configure-lz-adapter

configure-lz-adapter-arbitrum-sepolia: PEERS = [11155111]
configure-lz-adapter-arbitrum-sepolia: CHAIN=arbitrum-sepolia
configure-lz-adapter-arbitrum-sepolia: configure-lz-adapter

# Safe multisig propose variants: write a Safe Transaction Builder batch to safe/<chainid>-*.json
# (no broadcast). Import the file into the Safe UI to execute via the multisig.
propose-configure-portal:
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/configure/ProposeConfigurePortal.s.sol:ProposeConfigurePortal \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(CHAIN) \
	--skip test --non-interactive

propose-configure-portal-local: PEERS = [42161]
propose-configure-portal-local: CHAIN=localhost
propose-configure-portal-local: propose-configure-portal

propose-configure-portal-mainnet: PEERS = [42161]
propose-configure-portal-mainnet: CHAIN=mainnet
propose-configure-portal-mainnet: propose-configure-portal

propose-configure-portal-arbitrum: PEERS = [1]
propose-configure-portal-arbitrum: CHAIN=arbitrum
propose-configure-portal-arbitrum: propose-configure-portal

propose-configure-lz-adapter:
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/configure/ProposeConfigureLayerZero.s.sol:ProposeConfigureLayerZero \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(CHAIN) \
	--skip test --non-interactive

propose-configure-lz-adapter-local: PEERS = [42161]
propose-configure-lz-adapter-local: CHAIN=localhost
propose-configure-lz-adapter-local: propose-configure-lz-adapter

propose-configure-lz-adapter-mainnet: PEERS = [42161]
propose-configure-lz-adapter-mainnet: CHAIN=mainnet
propose-configure-lz-adapter-mainnet: propose-configure-lz-adapter

propose-configure-lz-adapter-arbitrum: PEERS = [1]
propose-configure-lz-adapter-arbitrum: CHAIN=arbitrum
propose-configure-lz-adapter-arbitrum: propose-configure-lz-adapter

# Bridge PYUSDX cross-chain via the PYUSDX Portal (default bridge adapter).
# DESTINATION_CHAIN_ID is the target chain ID (set by the per-network targets below).
# AMOUNT is the PYUSDX amount in base units (6 decimals); pass it on the CLI, e.g. AMOUNT=1000000.
# RECIPIENT is the destination recipient; the zero-address default routes to the signer.
# The signer (PRIVATE_KEY) must hold the PYUSDX and enough native gas for the bridge fee.
RECIPIENT ?= 0x0000000000000000000000000000000000000000

bridge:
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/execute/Bridge.s.sol:Bridge \
	--sig "run(uint32,uint256,address)" $(DESTINATION_CHAIN_ID) $(AMOUNT) $(RECIPIENT) \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive --broadcast

bridge-local: DESTINATION_CHAIN_ID=42161
bridge-local: CHAIN=localhost
bridge-local: bridge

bridge-mainnet-to-arbitrum: DESTINATION_CHAIN_ID=42161
bridge-mainnet-to-arbitrum: CHAIN=mainnet
bridge-mainnet-to-arbitrum: bridge

bridge-arbitrum-to-mainnet: DESTINATION_CHAIN_ID=1
bridge-arbitrum-to-mainnet: CHAIN=arbitrum
bridge-arbitrum-to-mainnet: bridge

bridge-sepolia-to-arbitrum-sepolia: DESTINATION_CHAIN_ID=421614
bridge-sepolia-to-arbitrum-sepolia: CHAIN=sepolia
bridge-sepolia-to-arbitrum-sepolia: bridge

bridge-arbitrum-sepolia-to-sepolia: DESTINATION_CHAIN_ID=11155111
bridge-arbitrum-sepolia-to-sepolia: CHAIN=arbitrum-sepolia
bridge-arbitrum-sepolia-to-sepolia: bridge

# Run slither
slither :; FOUNDRY_PROFILE=production forge build --build-info --skip '*/test/**' --skip '*/script/**' --force && slither --compile-force-framework foundry --ignore-compile --sarif results.sarif --config-file slither.config.json .

# Common tasks
profile ?=default

build:
	@./build.sh -p production

tests:
	@./test.sh -p $(profile)

fuzz:
	@./test.sh -t testFuzz -p $(profile)

integration:
	@./test.sh -d test/integration -p $(profile)

invariant:
	@./test.sh -d test/invariant -p $(profile)

coverage:
	FOUNDRY_PROFILE=$(profile) forge coverage --report lcov && lcov --ignore-errors inconsistent --extract lcov.info -o lcov.info 'src/*' && genhtml lcov.info -o coverage

gas-report:
	FOUNDRY_PROFILE=$(profile) forge test --gas-report > gasreport.ansi

sizes:
	@./build.sh -p production -s

clean:
	forge clean && rm -rf ./abi && rm -rf ./bytecode && rm -rf ./types
