// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
const hre = require("hardhat");

async function main() {
  console.log("Deploying AutoGrowingLPTokenV4 contract...");

  // Get the contract factory
  const AutoGrowingLPTokenV4 = await hre.ethers.getContractFactory("AutoGrowingLPTokenV4");
  
  // Deploy the contract with constructor arguments
  // Initial supply: 1,000,000 tokens (with 18 decimals)
  // Initial price: 0.0001 ETH per token
  const initialSupply = ethers.parseEther("1000000");
  const initialPrice = ethers.parseEther("0.0001");
  
  console.log("Deploying with the following parameters:");
  console.log(`Initial supply: ${ethers.formatEther(initialSupply)} tokens`);
  console.log(`Initial price: ${ethers.formatEther(initialPrice)} ETH per token`);
  
  const autoGrowingLPToken = await AutoGrowingLPTokenV4.deploy(
    initialSupply,
    initialPrice
  );

  // Wait for the contract to be deployed
  await autoGrowingLPToken.waitForDeployment();
  const deployedAddress = await autoGrowingLPToken.getAddress();

  console.log(`AutoGrowingLPTokenV4 deployed to: ${deployedAddress}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
