import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts to testnet with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Deploy Treasury first
  console.log("\n=== Deploying TitsTreasury ===");
  const TitsTreasury = await ethers.getContractFactory("TitsTreasury");
  const treasury = await TitsTreasury.deploy(deployer.address);
  await treasury.waitForDeployment();
  const treasuryAddress = await treasury.getAddress();
  console.log("TitsTreasury deployed to:", treasuryAddress);

  // Deploy TittyPoolFactory
  console.log("\n=== Deploying TittyPoolFactory ===");
  const TittyPoolFactory = await ethers.getContractFactory("TittyPoolFactory");
  const factory = await TittyPoolFactory.deploy(deployer.address);
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("TittyPoolFactory deployed to:", factoryAddress);

  // Deploy CryptoTittyFactory
  console.log("\n=== Deploying CryptoTittyFactory ===");
  const CryptoTittyFactory = await ethers.getContractFactory("CryptoTittyFactory");
  const tokenFactory = await CryptoTittyFactory.deploy(deployer.address);
  await tokenFactory.waitForDeployment();
  const tokenFactoryAddress = await tokenFactory.getAddress();
  console.log("CryptoTittyFactory deployed to:", tokenFactoryAddress);

  // Fund the treasury with some initial funds
  console.log("\n=== Funding Treasury ===");
  const fundingTx = await treasury.fundTreasury({ value: ethers.parseEther("1") });
  await fundingTx.wait();
  console.log("Treasury funded with 1 ETH");

  console.log("\n=== Testnet Deployment Summary ===");
  console.log("TitsTreasury:", treasuryAddress);
  console.log("TittyPoolFactory:", factoryAddress);
  console.log("CryptoTittyFactory:", tokenFactoryAddress);

  // Save deployment addresses
  const deploymentInfo = {
    treasury: treasuryAddress,
    factory: factoryAddress,
    tokenFactory: tokenFactoryAddress,
    network: "flowTestnet",
    deployer: deployer.address,
    timestamp: new Date().toISOString()
  };

  const fs = require('fs');
  fs.writeFileSync(
    'deployment-testnet.json', 
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log("\nDeployment info saved to deployment-testnet.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 