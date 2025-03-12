#!/bin/bash

# Deploy the AutoGrowingLPTokenV4 contract to Base Sepolia
cd /Users/abc/AutoGrowingLPToken

# Set the RPC URL for Base Sepolia
export RPC_URL="https://sepolia.base.org"

# Run the deployment script with increased memory limit
echo "Deploying AutoGrowingLPTokenV4 to Base Sepolia..."
pnpm exec forge script script/DeployBaseTestnet.sol:DeployBaseTestnet \
  --rpc-url $RPC_URL \
  --broadcast \
  --legacy \
  --gas-price 1500000000 \
  -vvvv

echo "Deployment completed."
