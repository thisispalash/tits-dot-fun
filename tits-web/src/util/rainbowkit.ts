'use client';

import '@rainbow-me/rainbowkit/styles.css';
import { connectorsForWallets } from '@rainbow-me/rainbowkit';
import { createConfig, http } from 'wagmi';
import { mainnet, flowMainnet } from 'viem/chains';
import { flowWallet } from './flowWallet';

/*
We can leave this as is for the tutorial but it should be
replaced with your own project ID for production use.
*/
const projectId = process.env.NEXT_PUBLIC_REOWN_PROJECT_ID as string;

const connectors = connectorsForWallets(
  [
    {
      groupName: 'Recommended',
      wallets: [flowWallet]
    },
  ],
  {
    appName: 'tits dot [dot] fun',
    projectId,
  }
);

export const config = createConfig({
  connectors,
  chains: [flowMainnet, mainnet],
  ssr: true,
  transports: {
    [flowMainnet.id]: http(),
    [mainnet.id]: http(),
  },
});
