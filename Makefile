# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# dapp deps
update:; forge update

# Deployment helpers
deploy:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) \
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
	forge script script/deploy/DeployAll.s.sol:DeployAll \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive --broadcast --verify

deploy-local: RPC_URL=$(LOCALHOST_RPC_URL)
deploy-local: deploy

deploy-mainnet: RPC_URL=$(MAINNET_RPC_URL)
deploy-mainnet: deploy

deploy-arbitrum: RPC_URL=$(ARBITRUM_RPC_URL)
deploy-arbitrum: deploy

deploy-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
deploy-sepolia: deploy

# Portal configuration helpers
# PEERS is a Solidity uint32[] literal of remote chain IDs, e.g. PEERS='[42161]'.
configure-portal: PEERS ?= []
configure-portal:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) \
	forge script script/configure/ConfigurePortal.s.sol:ConfigurePortal \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive --broadcast

configure-portal-local: PEERS ?= [42161]
configure-portal-local: RPC_URL=$(LOCALHOST_RPC_URL)
configure-portal-local: configure-portal

configure-portal-mainnet: PEERS ?= [42161]
configure-portal-mainnet: RPC_URL=$(MAINNET_RPC_URL)
configure-portal-mainnet: configure-portal

configure-portal-arbitrum: PEERS ?= [1]
configure-portal-arbitrum: RPC_URL=$(ARBITRUM_RPC_URL)
configure-portal-arbitrum: configure-portal

# LayerZero ULN/DVN security config. Signer must be the adapter's LayerZero delegate.
configure-lz-adapter: PEERS ?= []
configure-lz-adapter:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) \
	forge script script/configure/ConfigureLayerZero.s.sol:ConfigureLayerZero \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive --broadcast

configure-lz-adapter-local: PEERS ?= [42161]
configure-lz-adapter-local: RPC_URL=$(LOCALHOST_RPC_URL)
configure-lz-adapter-local: configure-lz-adapter

configure-lz-adapter-mainnet: PEERS ?= [42161]
configure-lz-adapter-mainnet: RPC_URL=$(MAINNET_RPC_URL)
configure-lz-adapter-mainnet: configure-lz-adapter

configure-lz-adapter-arbitrum: PEERS ?= [1]
configure-lz-adapter-arbitrum: RPC_URL=$(ARBITRUM_RPC_URL)
configure-lz-adapter-arbitrum: configure-lz-adapter

# Safe multisig propose variants: write a Safe Transaction Builder batch to safe/<chainid>-*.json
# (no broadcast). Import the file into the Safe UI to execute via the multisig.
propose-configure-portal: PEERS ?= []
propose-configure-portal:
	FOUNDRY_PROFILE=production \
	forge script script/configure/ProposeConfigurePortal.s.sol:ProposeConfigurePortal \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(RPC_URL) \
	--skip test --non-interactive

propose-configure-lz-adapter: PEERS ?= []
propose-configure-lz-adapter:
	FOUNDRY_PROFILE=production \
	forge script script/configure/ProposeConfigureLayerZero.s.sol:ProposeConfigureLayerZero \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(RPC_URL) \
	--skip test --non-interactive

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
