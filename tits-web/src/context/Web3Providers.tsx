'use client';

import { createContext, useContext, useState } from 'react';

import SupraProvider from './SupraProvider';
import FlowProvider from './FlowProvider';

interface Web3ProvidersContextType {
  address: string | null;
  setAddress: (address: string | null) => void;
  chain: string | null;
  setChain: (chain: 'supra' | 'flow') => void;
  getShortAddress: () => string;
}

const Web3ProvidersContext = createContext<Web3ProvidersContextType | null>(null);


export default function Web3Providers({ children }: { children: React.ReactNode }) {

  const [ address, setAddress ] = useState<string|null>(null);
  const [ chain, setChain ] = useState<'supra'|'flow'>('supra');

  const getShortAddress = () => {
    if (!address) return '';
    return address.slice(0, 6) + '..' + address.slice(-4);
  }

  return (
    <Web3ProvidersContext.Provider 
      value={{
        address,
        setAddress,
        chain,
        setChain,
        getShortAddress,
      }}
    >
      <SupraProvider>
        <FlowProvider>
          {children}
        </FlowProvider>
      </SupraProvider>
    </Web3ProvidersContext.Provider>
  );
}


export const useWeb3 = () => {
  const context = useContext(Web3ProvidersContext);
  if (!context) {
    throw new Error('useWeb3 must be used within a Web3Providers');
  }
  return context;
};