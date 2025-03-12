import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

// Private key for deployment
const PRIVATE_KEY = "0x89266ff69e24130a10d24dfb80316a2c6f3e2304345e8796aa820a3a19f27589";

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  networks: {
    // Ethereum mainnet
    mainnet: {
      url: "https://eth-mainnet.g.alchemy.com/v2/your-api-key", // Replace with your API key
      accounts: [PRIVATE_KEY],
    },
    // Sepolia testnet
    sepolia: {
      url: "https://eth-sepolia.public.blastapi.io", // Free public RPC endpoint
      accounts: [PRIVATE_KEY],
      gasPrice: 3000000000, // 3 Gwei
    },
    // Local development network
    hardhat: {
      chainId: 31337,
    },
  },
  etherscan: {
    apiKey: "your-etherscan-api-key", // Replace with your Etherscan API key for verification
  },
};

export default config;
