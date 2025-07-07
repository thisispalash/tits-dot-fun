import { Address } from "viem";
import { baseSepolia } from "viem/chains";
import { createCoinCall, DeployCurrency, ValidMetadataURI } from "@zoralabs/coins-sdk";
 
async function getPoolConfig() {
  const coinParams = {
    name: "Some Random Coin",
    symbol: "SRC",
    payoutRecipient: "0x0000000000000000000000000000000000000000" as Address,
    platformReferrer: "0x0000000000000000000000000000000000000000" as Address,
    
    // Some random ipfs uri, from docs ~ https://docs.zora.co/coins/sdk/create-coin#basic-creation
    uri: "ipfs://bafybeigoxzqzbnxsn35vq7lls3ljxdcwjafxvbvkivprsodzrptpiguysy" as ValidMetadataURI, 
    
    // The important part (for pool config)
    chainId: baseSepolia.id,
    currency: DeployCurrency.ETH,
  }
 
  try {
    const result = await createCoinCall(coinParams);
    const args = result.args;
    const poolConfig = args[5];

    console.log(poolConfig);

    return poolConfig;
  } catch (error) {
    console.error("Error creating coin call:", error);
    throw error;
  }
}

getPoolConfig();