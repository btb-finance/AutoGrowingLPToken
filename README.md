# AutoGrowingLPToken for Uniswap V4

This project implements an innovative ERC20 token with automatic price growth and liquidity building mechanisms using Uniswap V4 hooks.

## Key Features

- **Automatic Price Growth**: Token price increases by 0.1% for each 1 ETH of purchase volume
- **Self-Building Liquidity**: 50% of purchase ETH is automatically added to Uniswap V4 liquidity
- **Fee Recycling**: Trading fees are collected and used to burn tokens, creating a deflationary mechanism
- **Full Range Position**: All liquidity is added to a single full-range position
- **Uniswap V4 Integration**: Leverages Uniswap V4 hooks for efficient pool interactions

## How It Works

1. Users buy tokens directly from the contract
2. Each purchase increases the token price according to volume
3. Half of the ETH goes to development, half to liquidity
4. Trading fees are periodically collected and used to burn tokens
5. The combination of price growth, liquidity building, and token burning creates a potential value appreciation mechanism

## Development

This project uses Hardhat for Ethereum development. To get started:

```shell
pnpm install
pnpm hardhat compile
pnpm hardhat test
```
