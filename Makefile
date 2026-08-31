# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# dapp deps
update:; forge update

# Uses the 1Password CLI to inject secrets referenced in .env into the forge process.
# In .env, set secret values as 1Password references, e.g. PRIVATE_KEY="op://vault/item/field".
# `op run` injects every .env var, so the scripts read them (PRIVATE_KEY, PYUSDX_*, etc.) directly via vm.env*.
OP_RUN := op run --env-file=".env" --

# Conditionally set broadcast and verify flags. DRY_RUN=true simulates without sending anything.
# BROADCAST_FLAGS is for targets that deploy contracts (they also verify on the explorer).
# EXECUTE_FLAGS is for targets that only send transactions -- there is nothing to verify.
ifeq ($(DRY_RUN),true)
	BROADCAST_FLAGS =
	EXECUTE_FLAGS =
else
	BROADCAST_FLAGS = --broadcast --verify
	EXECUTE_FLAGS = --broadcast
endif

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
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

deploy-local: CHAIN=localhost
deploy-local: deploy

deploy-mainnet: CHAIN=mainnet
deploy-mainnet: deploy

deploy-arbitrum: CHAIN=arbitrum
deploy-arbitrum: deploy

deploy-monad: CHAIN=monad
deploy-monad: deploy

deploy-base: CHAIN=base
deploy-base: deploy

deploy-sepolia: CHAIN=sepolia
deploy-sepolia: deploy

deploy-arbitrum-sepolia: CHAIN=arbitrum-sepolia
deploy-arbitrum-sepolia: deploy

deploy-monad-testnet: CHAIN=monad-testnet
deploy-monad-testnet: deploy

deploy-base-sepolia: CHAIN=base-sepolia
deploy-base-sepolia: deploy

# Extension deploys (via the ExtensionFactory). Both read the factory address from
# deployments/<chainid>.json, falling back to the EXTENSION_FACTORY env var.
EXTENSION_ENV = \
	EXTENSION_NAME="$(EXTENSION_NAME)" EXTENSION_TOKEN_NAME="$(EXTENSION_TOKEN_NAME)" \
	EXTENSION_TOKEN_SYMBOL=$(EXTENSION_TOKEN_SYMBOL) YIELD_RECIPIENT=$(YIELD_RECIPIENT) \
	ADMIN=$(ADMIN) FREEZE_MANAGER=$(FREEZE_MANAGER) PAUSER=$(PAUSER) \
	YIELD_RECIPIENT_MANAGER=$(YIELD_RECIPIENT_MANAGER) VERSION_MANAGER=$(VERSION_MANAGER) \
	EXTENSION_FACTORY=$(EXTENSION_FACTORY)

deploy-yield-to-one:
	$(EXTENSION_ENV) \
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/deploy/DeployYieldToOne.s.sol:DeployYieldToOne \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

deploy-yield-to-one-local: CHAIN=localhost
deploy-yield-to-one-local: deploy-yield-to-one

deploy-yield-to-one-mainnet: CHAIN=mainnet
deploy-yield-to-one-mainnet: deploy-yield-to-one

deploy-yield-to-one-arbitrum: CHAIN=arbitrum
deploy-yield-to-one-arbitrum: deploy-yield-to-one

deploy-yield-to-one-sepolia: CHAIN=sepolia
deploy-yield-to-one-sepolia: deploy-yield-to-one

deploy-yield-to-one-arbitrum-sepolia: CHAIN=arbitrum-sepolia
deploy-yield-to-one-arbitrum-sepolia: deploy-yield-to-one

# MultiMint config comes from deploymentConfigs/<chainid>/$(EXTENSION_NAME).json (schema:
# deploymentConfigs/README.md); EXTENSION_CONFIG optionally overrides the path.
deploy-multi-mint:
	EXTENSION_NAME="$(EXTENSION_NAME)" EXTENSION_FACTORY=$(EXTENSION_FACTORY) \
	$(if $(EXTENSION_CONFIG),EXTENSION_CONFIG="$(EXTENSION_CONFIG)") \
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/deploy/DeployMultiMint.s.sol:DeployMultiMint \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

deploy-multi-mint-local: CHAIN=localhost
deploy-multi-mint-local: deploy-multi-mint

deploy-multi-mint-mainnet: CHAIN=mainnet
deploy-multi-mint-mainnet: deploy-multi-mint

deploy-multi-mint-arbitrum: CHAIN=arbitrum
deploy-multi-mint-arbitrum: deploy-multi-mint

deploy-multi-mint-sepolia: CHAIN=sepolia
deploy-multi-mint-sepolia: deploy-multi-mint

deploy-multi-mint-arbitrum-sepolia: CHAIN=arbitrum-sepolia
deploy-multi-mint-arbitrum-sepolia: deploy-multi-mint

# Usage: make deploy-portal-oft-wrapper CHAIN=mainnet
deploy-portal-oft-wrapper:
	PORTAL_OFT_WRAPPER_ADMIN=$(PORTAL_OFT_WRAPPER_ADMIN) \
	PORTAL_OFT_WRAPPER_OPERATOR=$(PORTAL_OFT_WRAPPER_OPERATOR) \
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/deploy/DeployPortalOFTWrapper.s.sol:DeployPortalOFTWrapper \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

# Register/update a collateral type on a deployed MultiMint extension by setting its asset cap.
# A non-zero ASSET_CAP registers ASSET as allowed collateral (enables wrap/replaceAsset); 0 disables it.
# The MultiMint address resolves from deployments/<chainid>.json by EXTENSION_NAME, or set MULTI_MINT directly.
# ASSET_CAP is denominated in ASSET's decimals. The signer (PRIVATE_KEY) must hold ASSET_CAP_MANAGER_ROLE.
configure-multi-mint-asset-cap:
	EXTENSION_NAME="$(EXTENSION_NAME)" MULTI_MINT=$(MULTI_MINT) ASSET=$(ASSET) ASSET_CAP=$(ASSET_CAP) \
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/configure/ConfigureMultiMintAssetCap.s.sol:ConfigureMultiMintAssetCap \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive $(EXECUTE_FLAGS)

configure-multi-mint-asset-cap-local: CHAIN=localhost
configure-multi-mint-asset-cap-local: configure-multi-mint-asset-cap

configure-multi-mint-asset-cap-mainnet: CHAIN=mainnet
configure-multi-mint-asset-cap-mainnet: configure-multi-mint-asset-cap

configure-multi-mint-asset-cap-arbitrum: CHAIN=arbitrum
configure-multi-mint-asset-cap-arbitrum: configure-multi-mint-asset-cap

configure-multi-mint-asset-cap-sepolia: CHAIN=sepolia
configure-multi-mint-asset-cap-sepolia: configure-multi-mint-asset-cap

configure-multi-mint-asset-cap-arbitrum-sepolia: CHAIN=arbitrum-sepolia
configure-multi-mint-asset-cap-arbitrum-sepolia: configure-multi-mint-asset-cap

# Testnet faucet (periphery, non-upgradeable). Reads the PYUSDX address from deployments/<chainid>.json,
# falling back to the PYUSDX env var. Pre-fund the deployed faucet with PYUSDX so it has a balance to dispense.
deploy-faucet:
	PYUSDX=$(PYUSDX) \
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/periphery/DeployPYUSDXFaucet.s.sol:DeployPYUSDXFaucet \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

deploy-faucet-sepolia: CHAIN=sepolia
deploy-faucet-sepolia: deploy-faucet

deploy-faucet-arbitrum-sepolia: CHAIN=arbitrum-sepolia
deploy-faucet-arbitrum-sepolia: deploy-faucet

deploy-faucet-base-sepolia: CHAIN=base-sepolia
deploy-faucet-base-sepolia: deploy-faucet

# Portal configuration helpers
# PEERS is a Solidity uint32[] literal of remote chain IDs. It defaults to an empty array and is set
# by the per-network targets below; override on the CLI with PEERS='[...]'.
PEERS ?= []

configure-portal:
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/configure/ConfigurePortal.s.sol:ConfigurePortal \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive $(EXECUTE_FLAGS)

configure-portal-local: PEERS = [42161]
configure-portal-local: CHAIN=localhost
configure-portal-local: configure-portal

configure-portal-mainnet: PEERS = [42161,143,8453]
configure-portal-mainnet: CHAIN=mainnet
configure-portal-mainnet: configure-portal

configure-portal-arbitrum: PEERS = [1,143]
configure-portal-arbitrum: CHAIN=arbitrum
configure-portal-arbitrum: configure-portal

configure-portal-monad: PEERS = [1,42161]
configure-portal-monad: CHAIN=monad
configure-portal-monad: configure-portal

configure-portal-base: PEERS = [1]
configure-portal-base: CHAIN=base
configure-portal-base: configure-portal

configure-portal-sepolia: PEERS = [421614,10143,84532]
configure-portal-sepolia: CHAIN=sepolia
configure-portal-sepolia: configure-portal

configure-portal-arbitrum-sepolia: PEERS = [11155111]
configure-portal-arbitrum-sepolia: CHAIN=arbitrum-sepolia
configure-portal-arbitrum-sepolia: configure-portal

configure-portal-monad-testnet: PEERS = [11155111]
configure-portal-monad-testnet: CHAIN=monad-testnet
configure-portal-monad-testnet: configure-portal

configure-portal-base-sepolia: PEERS = [11155111]
configure-portal-base-sepolia: CHAIN=base-sepolia
configure-portal-base-sepolia: configure-portal

# LayerZero ULN/DVN security config. Signer must be the adapter's LayerZero delegate.
configure-lz-adapter:
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/configure/ConfigureLayerZero.s.sol:ConfigureLayerZero \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(CHAIN) \
	--skip test --slow --non-interactive $(EXECUTE_FLAGS)

configure-lz-adapter-local: PEERS = [42161]
configure-lz-adapter-local: CHAIN=localhost
configure-lz-adapter-local: configure-lz-adapter

configure-lz-adapter-mainnet: PEERS = [42161,143,8453]
configure-lz-adapter-mainnet: CHAIN=mainnet
configure-lz-adapter-mainnet: configure-lz-adapter

configure-lz-adapter-arbitrum: PEERS = [1,143]
configure-lz-adapter-arbitrum: CHAIN=arbitrum
configure-lz-adapter-arbitrum: configure-lz-adapter

configure-lz-adapter-monad: PEERS = [1,42161]
configure-lz-adapter-monad: CHAIN=monad
configure-lz-adapter-monad: configure-lz-adapter

configure-lz-adapter-base: PEERS = [1]
configure-lz-adapter-base: CHAIN=base
configure-lz-adapter-base: configure-lz-adapter

configure-lz-adapter-sepolia: PEERS = [421614,10143,84532]
configure-lz-adapter-sepolia: CHAIN=sepolia
configure-lz-adapter-sepolia: configure-lz-adapter

configure-lz-adapter-arbitrum-sepolia: PEERS = [11155111]
configure-lz-adapter-arbitrum-sepolia: CHAIN=arbitrum-sepolia
configure-lz-adapter-arbitrum-sepolia: configure-lz-adapter

configure-lz-adapter-monad-testnet: PEERS = [11155111]
configure-lz-adapter-monad-testnet: CHAIN=monad-testnet
configure-lz-adapter-monad-testnet: configure-lz-adapter

configure-lz-adapter-base-sepolia: PEERS = [11155111]
configure-lz-adapter-base-sepolia: CHAIN=base-sepolia
configure-lz-adapter-base-sepolia: configure-lz-adapter

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

propose-configure-portal-mainnet: PEERS = [42161,143,8453]
propose-configure-portal-mainnet: CHAIN=mainnet
propose-configure-portal-mainnet: propose-configure-portal

propose-configure-portal-arbitrum: PEERS = [1,143]
propose-configure-portal-arbitrum: CHAIN=arbitrum
propose-configure-portal-arbitrum: propose-configure-portal

propose-configure-portal-monad: PEERS = [1,42161]
propose-configure-portal-monad: CHAIN=monad
propose-configure-portal-monad: propose-configure-portal

propose-configure-portal-base: PEERS = [1]
propose-configure-portal-base: CHAIN=base
propose-configure-portal-base: propose-configure-portal

propose-configure-lz-adapter:
	FOUNDRY_PROFILE=production $(OP_RUN) \
	forge script script/configure/ProposeConfigureLayerZero.s.sol:ProposeConfigureLayerZero \
	--sig "run(uint32[])" $(PEERS) \
	--rpc-url $(CHAIN) \
	--skip test --non-interactive

propose-configure-lz-adapter-local: PEERS = [42161]
propose-configure-lz-adapter-local: CHAIN=localhost
propose-configure-lz-adapter-local: propose-configure-lz-adapter

propose-configure-lz-adapter-mainnet: PEERS = [42161,143,8453]
propose-configure-lz-adapter-mainnet: CHAIN=mainnet
propose-configure-lz-adapter-mainnet: propose-configure-lz-adapter

propose-configure-lz-adapter-arbitrum: PEERS = [1,143]
propose-configure-lz-adapter-arbitrum: CHAIN=arbitrum
propose-configure-lz-adapter-arbitrum: propose-configure-lz-adapter

propose-configure-lz-adapter-monad: PEERS = [1,42161]
propose-configure-lz-adapter-monad: CHAIN=monad
propose-configure-lz-adapter-monad: propose-configure-lz-adapter

propose-configure-lz-adapter-base: PEERS = [1]
propose-configure-lz-adapter-base: CHAIN=base
propose-configure-lz-adapter-base: propose-configure-lz-adapter

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
	--skip test --slow --non-interactive $(EXECUTE_FLAGS)

bridge-local: DESTINATION_CHAIN_ID=42161
bridge-local: CHAIN=localhost
bridge-local: bridge

bridge-mainnet-to-arbitrum: DESTINATION_CHAIN_ID=42161
bridge-mainnet-to-arbitrum: CHAIN=mainnet
bridge-mainnet-to-arbitrum: bridge

bridge-arbitrum-to-mainnet: DESTINATION_CHAIN_ID=1
bridge-arbitrum-to-mainnet: CHAIN=arbitrum
bridge-arbitrum-to-mainnet: bridge

bridge-mainnet-to-monad: DESTINATION_CHAIN_ID=143
bridge-mainnet-to-monad: CHAIN=mainnet
bridge-mainnet-to-monad: bridge

bridge-monad-to-mainnet: DESTINATION_CHAIN_ID=1
bridge-monad-to-mainnet: CHAIN=monad
bridge-monad-to-mainnet: bridge

bridge-mainnet-to-base: DESTINATION_CHAIN_ID=8453
bridge-mainnet-to-base: CHAIN=mainnet
bridge-mainnet-to-base: bridge

bridge-base-to-mainnet: DESTINATION_CHAIN_ID=1
bridge-base-to-mainnet: CHAIN=base
bridge-base-to-mainnet: bridge

bridge-arbitrum-to-monad: DESTINATION_CHAIN_ID=143
bridge-arbitrum-to-monad: CHAIN=arbitrum
bridge-arbitrum-to-monad: bridge

bridge-monad-to-arbitrum: DESTINATION_CHAIN_ID=42161
bridge-monad-to-arbitrum: CHAIN=monad
bridge-monad-to-arbitrum: bridge

bridge-sepolia-to-arbitrum-sepolia: DESTINATION_CHAIN_ID=421614
bridge-sepolia-to-arbitrum-sepolia: CHAIN=sepolia
bridge-sepolia-to-arbitrum-sepolia: bridge

bridge-arbitrum-sepolia-to-sepolia: DESTINATION_CHAIN_ID=11155111
bridge-arbitrum-sepolia-to-sepolia: CHAIN=arbitrum-sepolia
bridge-arbitrum-sepolia-to-sepolia: bridge

bridge-sepolia-to-monad-testnet: DESTINATION_CHAIN_ID=10143
bridge-sepolia-to-monad-testnet: CHAIN=sepolia
bridge-sepolia-to-monad-testnet: bridge

bridge-monad-testnet-to-sepolia: DESTINATION_CHAIN_ID=11155111
bridge-monad-testnet-to-sepolia: CHAIN=monad-testnet
bridge-monad-testnet-to-sepolia: bridge

bridge-sepolia-to-base-sepolia: DESTINATION_CHAIN_ID=84532
bridge-sepolia-to-base-sepolia: CHAIN=sepolia
bridge-sepolia-to-base-sepolia: bridge

bridge-base-sepolia-to-sepolia: DESTINATION_CHAIN_ID=11155111
bridge-base-sepolia-to-sepolia: CHAIN=base-sepolia
bridge-base-sepolia-to-sepolia: bridge

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
