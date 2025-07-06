import { ethers, upgrades } from "hardhat";
import { run } from "hardhat";

// Default pool configuration - replace this with the actual bytes from Zora's SDK
const DEFAULT_POOL_CONFIG = "0x0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000001fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc2f700000000000000000000000000000000000000000000000000000000000000001fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd06480000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000b000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000b1a2bc2ec50000";

async function main() {
  console.log("Deploying TTCoiner contract...");

  // Get the deployer account
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Contract parameters
  const ZORA_FACTORY_ADDRESS = "0x777777751622c0d3258f214F9DF38E35BF45baF3"; // Base Sepolia
  const ADMIN_ADDRESS = deployer.address;

  console.log("Pool config length:", DEFAULT_POOL_CONFIG.length);
  console.log("Pool config:", DEFAULT_POOL_CONFIG);

  // Get the contract factory
  const TTCoiner = await ethers.getContractFactory("TTCoiner");

  // Deploy the proxy (this automatically deploys implementation too)
  console.log("Deploying TTCoiner proxy...");
  const ttCoiner = await upgrades.deployProxy(
    TTCoiner,
    [
      ZORA_FACTORY_ADDRESS,
      ADMIN_ADDRESS,
      DEFAULT_POOL_CONFIG
    ],
    {
      initializer: "initialize",
      kind: "uups"
    }
  );

  await ttCoiner.waitForDeployment();
  const proxyAddress = await ttCoiner.getAddress();

  console.log("TTCoiner proxy deployed to:", proxyAddress);

  // Wait a bit for the transaction to be fully mined
  console.log("Waiting for deployment to be fully confirmed...");
  await new Promise(resolve => setTimeout(resolve, 10000));

  // Get implementation address using a try-catch approach
  let implementationAddress;
  try {
    implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log("Implementation deployed to:", implementationAddress);
  } catch (error: any) {
    console.log("Could not get implementation address from ERC1967:", error.message);
    // Alternative: check the OpenZeppelin network file
    console.log("Implementation address will be verified during contract verification");
  }

  // Verify initialization using the contract instance directly
  console.log("\nVerifying initialization...");
  try {
    console.log("ZoraFactory address:", await ttCoiner.zoraFactory());
    console.log("Next coin ID:", await ttCoiner.nextCoinId());
    console.log("Next network ID:", await ttCoiner.nextNetworkId());
    console.log("Default platform referrer:", await ttCoiner.defaultPlatformReferrer());
    console.log("VERSION:", await ttCoiner.VERSION());

    // Check roles
    const DEFAULT_ADMIN_ROLE = await ttCoiner.DEFAULT_ADMIN_ROLE();
    const COIN_CREATOR_ROLE = await ttCoiner.COIN_CREATOR_ROLE();
    const UPGRADER_ROLE = await ttCoiner.UPGRADER_ROLE();
    const PAUSER_ROLE = await ttCoiner.PAUSER_ROLE();
    const NETWORK_MANAGER_ROLE = await ttCoiner.NETWORK_MANAGER_ROLE();

    console.log("\nRole assignments:");
    console.log("Has DEFAULT_ADMIN_ROLE:", await ttCoiner.hasRole(DEFAULT_ADMIN_ROLE, ADMIN_ADDRESS));
    console.log("Has COIN_CREATOR_ROLE:", await ttCoiner.hasRole(COIN_CREATOR_ROLE, ADMIN_ADDRESS));
    console.log("Has UPGRADER_ROLE:", await ttCoiner.hasRole(UPGRADER_ROLE, ADMIN_ADDRESS));
    console.log("Has PAUSER_ROLE:", await ttCoiner.hasRole(PAUSER_ROLE, ADMIN_ADDRESS));
    console.log("Has NETWORK_MANAGER_ROLE:", await ttCoiner.hasRole(NETWORK_MANAGER_ROLE, ADMIN_ADDRESS));

    console.log("\nInitialization verified successfully!");
  } catch (error: any) {
    console.error("Error during initialization verification:", error.message);
    console.log("This might indicate that the contract deployment failed or is still pending");
  }

  // Verify contracts on Etherscan using the enhanced verify task
  console.log("\nVerifying contracts on Etherscan...");
  try {
    await run("verify:verify", {
      address: proxyAddress,
    });
    console.log("Contracts verified successfully");
  } catch (error: any) {
    console.log("Verification failed or contracts already verified:", error.message);
  }

  // Save deployment info
  const deploymentInfo = {
    contractAddress: proxyAddress,
    implementationAddress: implementationAddress || "Unknown - check OpenZeppelin network files",
    proxyType: "UUPS",
    deployer: deployer.address,
    zoraFactory: ZORA_FACTORY_ADDRESS,
    network: (await ethers.provider.getNetwork()).name,
    blockNumber: await ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString()
  };

  console.log("\nDeployment Info:", JSON.stringify(deploymentInfo, null, 2));
  
  if (!implementationAddress) {
    console.log("\n=== Verification Commands ===");
    console.log(`npx hardhat verify --network baseSepolia ${proxyAddress}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
