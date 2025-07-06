# Coin Contracts

The contracts in this folder are related to Zora's Coins.



## Deployment Info
> Script :: [`deployCoiner.ts`](../../scripts/deployCoiner.ts)

Proxy :: [`0xA5bABC23787f4B3cf14c5c4f541338b5c047b8a6`](https://sepolia.basescan.org/address/0xa5babc23787f4b3cf14c5c4f541338b5c047b8a6) \
Impl :: [`0x91Ec1e7f6E87ae1Dd1d36918425Fd6A57e2C79A7`](https://sepolia.basescan.org/address/0x91ec1e7f6e87ae1dd1d36918425fd6a57e2c79a7)

CMD Output ~
```sh
➞  npx hardhat run scripts/deployCoiner.ts --network baseSepolia
Compiled 1 Solidity file successfully (evm target: paris).
Deploying TTCoiner contract...
Deploying with account: 0x96e03e38aD4B5EF728f4C5F305eddBB509B652d0
Account balance: 15687417517091414961
Pool config length: 2
Pool config: 0x
Deploying TTCoiner proxy...
TTCoiner proxy deployed to: 0xA5bABC23787f4B3cf14c5c4f541338b5c047b8a6
Waiting for deployment to be fully confirmed...
Implementation deployed to: 0x91Ec1e7f6E87ae1Dd1d36918425Fd6A57e2C79A7

Verifying initialization...
ZoraFactory address: 0x777777751622c0d3258f214F9DF38E35BF45baF3
Next coin ID: 1n
Next network ID: 1n
Default platform referrer: 0xA5bABC23787f4B3cf14c5c4f541338b5c047b8a6
VERSION: 0.1.0

Role assignments:
Has DEFAULT_ADMIN_ROLE: true
Has COIN_CREATOR_ROLE: true
Has UPGRADER_ROLE: true
Has PAUSER_ROLE: true
Has NETWORK_MANAGER_ROLE: true

Initialization verified successfully!

Verifying contracts on Etherscan...
Verifying implementation: 0x91Ec1e7f6E87ae1Dd1d36918425Fd6A57e2C79A7
Successfully submitted source code for contract
contracts/Coin/TTCoiner.sol:TTCoiner at 0x91Ec1e7f6E87ae1Dd1d36918425Fd6A57e2C79A7
for verification on the block explorer. Waiting for verification result...

Successfully verified contract TTCoiner on the block explorer.
https://sepolia.basescan.org/address/0x91Ec1e7f6E87ae1Dd1d36918425Fd6A57e2C79A7#code

Verifying proxy: 0xA5bABC23787f4B3cf14c5c4f541338b5c047b8a6
Failed to verify ERC1967Proxy contract at 0xA5bABC23787f4B3cf14c5c4f541338b5c047b8a6: Already Verified
Linking proxy 0xA5bABC23787f4B3cf14c5c4f541338b5c047b8a6 with implementation
Successfully linked proxy to implementation.
Verification failed or contracts already verified: 
Verification completed with the following errors.

Error 1: Failed to verify ERC1967Proxy contract at 0xA5bABC23787f4B3cf14c5c4f541338b5c047b8a6: Already Verified



Deployment Info: {
  "contractAddress": "0xA5bABC23787f4B3cf14c5c4f541338b5c047b8a6",
  "implementationAddress": "0x91Ec1e7f6E87ae1Dd1d36918425Fd6A57e2C79A7",
  "proxyType": "UUPS",
  "deployer": "0x96e03e38aD4B5EF728f4C5F305eddBB509B652d0",
  "zoraFactory": "0x777777751622c0d3258f214F9DF38E35BF45baF3",
  "network": "baseSepolia",
  "blockNumber": 28012151,
  "timestamp": "2025-07-06T09:03:12.503Z"
}
```