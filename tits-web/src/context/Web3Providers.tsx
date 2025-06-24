'use client'

import React, { type ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { cookieToInitialState, WagmiProvider, type Config } from 'wagmi'

import { createAppKit } from '@reown/appkit'

import { wagmiAdapter, projectId, networks } from '@/util/wagmi'
import { flowTestnet } from 'wagmi/chains'

if (!projectId) {
  throw new Error('Project ID is not defined')
}

// Set up metadata
const metadata = {
  name: 'tits dot [dot] fun',
  description: 'Can humanity coordinate?',
  url: 'http://localhost:3000', // origin must match your domain & subdomain
  icons: []
}

// Create the modal
export const modal = createAppKit({
  adapters: [wagmiAdapter],
  projectId,
  networks,
  defaultNetwork: flowTestnet,
  metadata: metadata,
  enableWalletConnect: false,
  features: {
    analytics: true,
    swaps: false,
    connectMethodsOrder: ['wallet', 'social', 'email'],
  },
  includeWalletIds: [
    'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96', // MetaMask
    '19177a98252e07ddfc9af2083ba8e07ef627cb6103467ffebb3f8f4205fd7927', // Ledger
    'fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa', // Coinbase
  ],
  featuredWalletIds: [
    'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96', // MetaMask
  ],
  allWallets: 'ONLY_MOBILE',
  themeMode: 'dark',
  themeVariables: {
    '--w3m-font-family': 'var(--font-default)',
    '--w3m-accent': 'var(--background)',
    '--w3m-color-mix': 'var(--background)',
    '--w3m-color-mix-strength': 10
  },
});

// Set up queryClient
const queryClient = new QueryClient()

function ContextProvider({ children, cookies }: { children: ReactNode; cookies: string | null }) {
  const initialState = cookieToInitialState(wagmiAdapter.wagmiConfig as Config, cookies)

  return (
    <WagmiProvider config={wagmiAdapter.wagmiConfig as Config} initialState={initialState}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}

export default ContextProvider;