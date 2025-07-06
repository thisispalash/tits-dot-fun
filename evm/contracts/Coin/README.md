# Coin Contracts
> The contracts in this folder deal with Zora Coins

The core idea here is that for every completed (ie, time limit exceeded or locked) pool on any 
chain, there should be a new Coin created representing that pool for the creator of the pool (ie, 
the one who defined the game and curve options). In practice, that looks like the winner of 
$`\text{pool}_i`$ gets to Coin $`\text{pool}_{i+1}`$.

> [!NOTE]
> The project began as an exploration of the question, _can the trading charts be considered a new 
> medium of expression?_ \
> Coins and Zora is an effort to cement that lore. 

## Coin Parameters

| param | value | reason |
| :---: | :---: | --- |
| name | `TT {pool_id} on {network}` | Pool is network specific |
| symbol | `TT{coin_id}` | Uniqueness within a collection (ie, `"TT"`) across all networks |
| uri | `https://titsdot.fun/g/{network}/{pool_id}.json` | Control over metadata; removing `.json` provides interactive experience |
| poolConfig |  | | 
| platformReferrer | `address({TTCoiner-Proxy})` | Another revenue stream? |


## Extensions

One extension to this architecture might be creating Smart Wallets for all users of the protocol. 
This way, all the tokens remain on Base and are easier to manage. This also would help create a 
vibrant community on Base itself, especially since the protocol is intended to be deployed on any 
chain, not just evm specific!

Another extension to this architecture would be to support / integrate message passing between 
chains. This would make it so that a pool completion on any chain triggers a Coin creation. One 
cheap and easy way this can manifest is through the runner script, where it is technically 
automatic (so better than current), but still off chain.

Finally, fun things may be possible with a change in the `poolConfig` and any hooks. If we step 
back for a minute, the core reason for using Coins is to provide incentive to the players to win, 
as if they win, they get to define the next curve, and then earn on some secondary market (ie, 
Zora). Keeping this in mind, I think cool things are possible with tokenomics, especially as we get
into app chain territory with a protocol token. But, more on this later, since this likely requires
a bunch more research before any implementation!

## Deployment Info
> Script :: [`deployCoiner.ts`](../../scripts/deployCoiner.ts)

Proxy :: [`0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3`](https://sepolia.basescan.org/address/0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3) \
Impl :: [`0xe0Af9766439F47D85870707022d456F6AF3a7Ef0`](https://sepolia.basescan.org/address/0xe0Af9766439F47D85870707022d456F6AF3a7Ef0)

CMD Output ~
```sh
➞  npx hardhat run scripts/deployCoiner.ts --network baseSepolia                                                                                                                                                                                    [git:3-zora] ✖  
Deploying TTCoiner contract...
Deploying with account: 0x96e03e38aD4B5EF728f4C5F305eddBB509B652d0
Account balance: 15687406689676217554
Pool config length: 898
Pool config: 0x0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000001fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc2f700000000000000000000000000000000000000000000000000000000000000001fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd06480000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000b000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000b1a2bc2ec50000
Deploying TTCoiner proxy...
TTCoiner proxy deployed to: 0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3
Waiting for deployment to be fully confirmed...
Implementation deployed to: 0xe0Af9766439F47D85870707022d456F6AF3a7Ef0

Verifying initialization...
ZoraFactory address: 0x777777751622c0d3258f214F9DF38E35BF45baF3
Next coin ID: 1n
Next network ID: 1n
Default platform referrer: 0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3
VERSION: 1.0.0

Role assignments:
Has DEFAULT_ADMIN_ROLE: true
Has COIN_CREATOR_ROLE: true
Has UPGRADER_ROLE: true
Has PAUSER_ROLE: true
Has NETWORK_MANAGER_ROLE: true

Initialization verified successfully!

Verifying contracts on Etherscan...
Verifying implementation: 0xe0Af9766439F47D85870707022d456F6AF3a7Ef0
Successfully submitted source code for contract
contracts/Coin/TTCoiner.sol:TTCoiner at 0xe0Af9766439F47D85870707022d456F6AF3a7Ef0
for verification on the block explorer. Waiting for verification result...

Successfully verified contract TTCoiner on the block explorer.
https://sepolia.basescan.org/address/0xe0Af9766439F47D85870707022d456F6AF3a7Ef0#code

Verifying proxy: 0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3
Failed to verify ERC1967Proxy contract at 0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3: Already Verified
Linking proxy 0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3 with implementation
Successfully linked proxy to implementation.
Verification failed or contracts already verified: 
Verification completed with the following errors.

Error 1: Failed to verify ERC1967Proxy contract at 0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3: Already Verified



Deployment Info: {
  "contractAddress": "0xBce325F0C8EB0DF87178Ac0594eBefE3a98D10f3",
  "implementationAddress": "0xe0Af9766439F47D85870707022d456F6AF3a7Ef0",
  "proxyType": "UUPS",
  "deployer": "0x96e03e38aD4B5EF728f4C5F305eddBB509B652d0",
  "zoraFactory": "0x777777751622c0d3258f214F9DF38E35BF45baF3",
  "network": "baseSepolia",
  "blockNumber": 28035454,
  "timestamp": "2025-07-06T21:59:58.018Z"
}
```