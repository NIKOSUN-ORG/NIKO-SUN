include .env

.PHONY: build test deploy verify

build:
	forge build

test:
	forge test

deploy:
	forge script script/DeploySolarToken.s.sol --rpc-url $(SYSCOIN_RPC_URL) --account $(ACCOUNT) --broadcast

deploy-fast:
	forge create src/SolarToken.sol:SolarTokenV3Optimized --rpc-url $(SYSCOIN_RPC_URL) --account $(ACCOUNT) --broadcast -vvvvv

verify:
	forge verify-contract \
  --rpc-url https://rpc.tanenbaum.io \
  --verifier blockscout \
  --verifier-url 'https://explorer.tanenbaum.io/api/' \
  $(ADDRESS) \
  [contractFile]:[contractName]