# Supra Modules

The code in [`titsFun`](./titsFun) represents the on-chain logic of the protocol.

Automation ~ [`pool_launcher::run_automation`](./titsFun/sources/automations/pool_launcher.move#L9)

```sh
supra move automation register \
  --task-max-gas-amount 5000 \
  --task-gas-price-cap 200 \
  --task-expiry-time-secs 1750689609 \
  --task-automation-fee-cap 144000000 \
  --function-id "0x5d9e5ddecdcaf31b27ccf90970574d4001fe819928bc811a9279347fc769ffb8::pool_launcher::run_automation" \
  --rpc-url https://rpc-testnet.supra.com
```