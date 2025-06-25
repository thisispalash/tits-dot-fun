import { ethers } from "hardhat";

async function main() {
  // Load deployment info
  const fs = require('fs');
  let deploymentInfo;
  
  try {
    deploymentInfo = JSON.parse(fs.readFileSync('deployment.json', 'utf8'));
  } catch (error) {
    console.log("No deployment.json found, trying deployment-testnet.json...");
    try {
      deploymentInfo = JSON.parse(fs.readFileSync('deployment-testnet.json', 'utf8'));
    } catch (error2) {
      console.error("No deployment files found. Please run deployment script first.");
      return;
    }
  }

  console.log("Verifying contracts on", deploymentInfo.network);

  // Verify Treasury
  console.log("\n=== Verifying TitsTreasury ===");
  try {
    await hre.run("verify:verify", {
      address: deploymentInfo.treasury,
      constructorArguments: [deploymentInfo.deployer],
    });
    console.log("TitsTreasury verified successfully!");
  } catch (error) {
    console.log("TitsTreasury verification failed:", error.message);
  }

  // Verify TittyPoolFactory
  console.log("\n=== Verifying TittyPoolFactory ===");
  try {
    await hre.run("verify:verify", {
      address: deploymentInfo.factory,
      constructorArguments: [deploymentInfo.deployer],
    });
    console.log("TittyPoolFactory verified successfully!");
  } catch (error) {
    console.log("TittyPoolFactory verification failed:", error.message);
  }

  // Verify CryptoTittyFactory
  console.log("\n=== Verifying CryptoTittyFactory ===");
  try {
    await hre.run("verify:verify", {
      address: deploymentInfo.tokenFactory,
      constructorArguments: [deploymentInfo.deployer],
    });
    console.log("CryptoTittyFactory verified successfully!");
  } catch (error) {
    console.log("CryptoTittyFactory verification failed:", error.message);
  }

  console.log("\n=== Verification Complete ===");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 