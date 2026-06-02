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
