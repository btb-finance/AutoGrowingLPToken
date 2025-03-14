#!/bin/bash

# Script to deploy AutoGrowingLPTokenV4 to Base Sepolia
echo "Deploying AutoGrowingLPTokenV4 to Base Sepolia..."

# Make sure you have your private key in an .env file or set it here
# export PRIVATE_KEY=your_private_key_here

# Run the deployment script
pnpm exec forge script script/DeployBaseTestnet.sol:DeployBaseTestnet --rpc-url base_sepolia --broadcast --verify

echo "Deployment completed!"
