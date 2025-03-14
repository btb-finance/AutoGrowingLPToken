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
- `script/DeployBaseTestnet.sol`: Deployment script for Base Sepolia testnet
- `script/DeployTokenHook.s.sol`: Deployment script for local testing
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

## Base Sepolia Testnet Deployment

The project is already deployed on Base Sepolia testnet at address: `0x6121E72870F6a7a782Bd746A07245d90162c1440`

To deploy your own instance to Base Sepolia, follow these steps:

### 1. Update Deployment Configuration

Edit the `script/DeployBaseTestnet.sol` file to set your configuration:

```solidity
// Configuration parameters
string public constant TOKEN_NAME = "AutoGrowingLPToken";
string public constant TOKEN_SYMBOL = "AGLP";
address public constant DEV_WALLET = 0xYourDevWalletAddress; // Update with your wallet
uint160 public constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // 1:1 price

// Base Sepolia PoolManager address (this is the correct address for Base Sepolia)
address public constant POOL_MANAGER_ADDRESS = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;

// Canonical CREATE2 factory address (same on all EVM chains including Base Sepolia)
address public constant SINGLETON_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;

// Your private key - IMPORTANT: Handle this securely!
uint256 constant PRIVATE_KEY = 0xYourPrivateKeyHere;
```

### 2. Run the Deployment Script

We've created a convenient deployment script for Base Sepolia. Run it with:

```bash
./deploy-base-sepolia.sh
```

This script:
1. Uses the canonical CREATE2 factory to deploy with deterministic addresses
2. Finds a salt that produces a valid hook address with the correct flags
3. Deploys the contract using the found salt
4. Initializes the Uniswap V4 pool

### 3. Verify the Contract on Base Sepolia Explorer

After deployment, verify your contract with:

```bash
./verify-contract.sh
```

Make sure to update the script with:
- Your contract address from the deployment
- Your Base Sepolia API key
- The correct constructor arguments

## How It Works: Base Sepolia Deployment

The deployment process for Base Sepolia uses a specific approach to ensure compatibility with Uniswap V4:

1. **Canonical CREATE2 Factory**: We use the EIP-2470 Singleton Factory at `0xce0042B868300000d44A59004Da54A005ffdcf9f` which exists at the same address on all EVM chains.

2. **Hook Address Mining**: Uniswap V4 requires hook addresses to have specific bits set in their address to indicate which hooks they implement. Our `HookMiner` utility finds a salt value that produces a valid hook address.

3. **Deployment**: The contract is deployed using the CREATE2 factory with the found salt, ensuring it has the correct address format.

4. **Pool Initialization**: After deployment, the script initializes the Uniswap V4 pool with the specified initial price.

## Interacting with the Token on Base Sepolia

After deployment, you can interact with the token using the following methods:

### Buying Tokens

Send ETH directly to the token contract to purchase tokens:

```bash
cast send <TOKEN_ADDRESS> --value <ETH_AMOUNT_IN_WEI> --rpc-url https://sepolia.base.org --private-key <PRIVATE_KEY>
```

### Checking Token Price

Get the current token price:

```bash
cast call <TOKEN_ADDRESS> "getCurrentPrice()" --rpc-url https://sepolia.base.org
```

### Collecting Fees

Trigger fee collection and token burning:

```bash
cast send <TOKEN_ADDRESS> "collectFeesAndBurn()" --rpc-url https://sepolia.base.org --private-key <PRIVATE_KEY>
```

## Requirements for Base Sepolia Deployment

1. **Base Sepolia Requirements**:
   - Private key with Base Sepolia ETH
   - Base Sepolia RPC URL (https://sepolia.base.org)
   - Base Sepolia API key for verification

2. **Security Considerations**:
   - Never commit your private key to Git
   - Consider using environment variables for sensitive information
   - Always verify your contract after deployment for transparency

## License

MIT
