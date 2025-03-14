#!/bin/bash

# Verify the AutoGrowingLPTokenV4 contract on Base Sepolia
cd /Users/abc/AutoGrowingLPToken

# Contract address from deployment
CONTRACT_ADDRESS="0x3f1C2df5E18F6071E5c9369AF6EBe3cE12091440"

# API key for verification
ETHERSCAN_API_KEY="9XI8M8BCN6M6UISZWA68BKTJIKHUWAXNS3"

echo "Verifying contract at address: $CONTRACT_ADDRESS"

# Run the verification command
pnpm exec forge verify-contract \
  --chain-id 84532 \
  --compiler-version "v0.8.26+commit.8a97fa7e" \
  --constructor-args $(cast abi-encode "constructor(string,string,address,address,address)" "AutoGrowingLPToken" "AGLP" "0xbe2680DC1752109b4344DbEB1072fd8Cd880e54b" "0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408" "0xbe2680DC1752109b4344DbEB1072fd8Cd880e54b") \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  $CONTRACT_ADDRESS \
  src/token.sol:AutoGrowingLPTokenV4

echo "Verification process completed."
