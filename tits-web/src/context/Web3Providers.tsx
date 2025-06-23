'use client';

import { createContext, useContext } from 'react';

import SupraProvider from './SupraProvider';

interface Web3ProvidersContextType {
  address: string;
  chainId: string;
}

const Web3ProvidersContext = createContext<Web3ProvidersContextType | null>(null);


export default function Web3Providers({ children }: { children: React.ReactNode }) {

  return (
    <Web3ProvidersContext.Provider 
      value={{
        address: '',
        chainId: '',
      }}
    >
      <SupraProvider>
        {children}
      </SupraProvider>
    </Web3ProvidersContext.Provider>
  );
}


export const useWeb3 = () => {
  return useContext(Web3ProvidersContext);
};