# AutoGrowingLPToken

AutoGrowingLPToken is an ERC20 token built on Uniswap V4 that automatically grows in price based on purchase volume. It implements Uniswap V4 hooks to manage liquidity and fees.

## Features

- **Auto-Growing Price**: Each 1 ETH of purchase volume increases the token price by 0.1%
- **Automatic Liquidity**: 50% of incoming ETH is automatically added to liquidity
- **Fee Collection**: The contract collects trading fees and burns tokens to further increase value
- **Owner Controls**: Owner can adjust fee parameters and distribution ratios

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) (v16 or later)
- [pnpm](https://pnpm.io/installation)

## Installation

1. Clone the repository:

```bash
git clone https://github.com/yourusername/AutoGrowingLPToken.git
cd AutoGrowingLPToken
```

2. Install dependencies:

```bash
pnpm install
forge install
```

## Project Structure

- `src/token.sol`: Main token contract implementing Uniswap V4 hooks
- `script/DeployTokenHook.s.sol`: Deployment script for the token
- `test/utils/HookMiner.sol`: Utility for mining hook addresses with specific flags

## Local Deployment

### 1. Start a Local Ethereum Node

Start Anvil (local Ethereum node):

```bash
anvil
```

This will start a local Ethereum node at `http://localhost:8545` with predefined accounts and private keys.

### 2. Deploy the Uniswap V4 PoolManager

Before deploying the token, you need to deploy the Uniswap V4 PoolManager contract:

```bash
# Deploy the PoolManager contract
forge script script/DeployPoolManager.s.sol:DeployPoolManager --rpc-url http://localhost:8545 --broadcast
```

Note the address of the deployed PoolManager contract. You'll need to update the `POOL_MANAGER_ADDRESS` in the `DeployTokenHook.s.sol` script.

### 3. Update Deployment Configuration

Edit the `script/DeployTokenHook.s.sol` file to set your desired configuration:

```solidity
// Configuration parameters
string public constant TOKEN_NAME = "AutoGrowingLPToken";
string public constant TOKEN_SYMBOL = "AGLP";
address public constant DEV_WALLET = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Using the second anvil account
uint160 public constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // 1:1 price

// PoolManager address (update this with your deployed PoolManager address)
address public constant POOL_MANAGER_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
```

### 4. Deploy the Token

Deploy the AutoGrowingLPToken contract:

```bash
forge script script/DeployTokenHook.s.sol:DeployTokenHook --rpc-url http://localhost:8545 --broadcast -vvv
```

This will:
1. Mine a hook address with the correct flags
2. Deploy the token contract to the mined address
3. Initialize the pool with the specified price

## Testnet Deployment

To deploy to a testnet (e.g., Sepolia), follow these steps:

### 1. Set Up Environment Variables

Create a `.env` file with your private key and RPC URL:

```
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=your_sepolia_rpc_url
ETHERSCAN_API_KEY=your_etherscan_api_key
```

Load the environment variables:

```bash
source .env
```

### 2. Update Deployment Script for Testnet

Edit the `script/DeployTokenHook.s.sol` file to use your private key and the correct PoolManager address on the testnet:

```solidity
// Default private key (replace with your own or use environment variable)
uint256 constant PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

// PoolManager address on testnet (replace with the actual address)
address public constant POOL_MANAGER_ADDRESS = 0x...; // Testnet PoolManager address
```

### 3. Deploy to Testnet

Deploy the token to the testnet:

```bash
forge script script/DeployTokenHook.s.sol:DeployTokenHook --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvv
```

The `--verify` flag will attempt to verify the contract on Etherscan if you've provided an API key.

## Interacting with the Token

After deployment, you can interact with the token using the following methods:

### Buying Tokens

Send ETH directly to the token contract to purchase tokens:

```bash
cast send <TOKEN_ADDRESS> --value <ETH_AMOUNT_IN_WEI> --rpc-url http://localhost:8545 --private-key <PRIVATE_KEY>
```

### Checking Token Price

Get the current token price:

```bash
cast call <TOKEN_ADDRESS> "getCurrentPrice()" --rpc-url http://localhost:8545
```

### Collecting Fees

Trigger fee collection and token burning:

```bash
cast send <TOKEN_ADDRESS> "collectFeesAndBurn()" --rpc-url http://localhost:8545 --private-key <PRIVATE_KEY>
```

## Requirements for Deployment

1. **Local Network**:
   - Anvil running
   - Foundry installed
   - Uniswap V4 PoolManager deployed

2. **Testnet**:
   - Private key with testnet ETH
   - RPC URL for the testnet
   - Uniswap V4 PoolManager deployed on the testnet
   - Etherscan API key (for verification)

## License

MIT
