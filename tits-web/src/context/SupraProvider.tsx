'use client';

import { createContext, useContext } from 'react';

interface SupraProviderContextType {
  address: string;
  chainId: string;
}

const SupraProviderContext = createContext<SupraProviderContextType | null>(null);


export default function SupraProvider({ children }: { children: React.ReactNode }) {

  return (
    <SupraProviderContext.Provider 
      value={{
        address: '',
        chainId: '',
      }}
    >
      {children}
    </SupraProviderContext.Provider>
  );
}


export const useSupra = () => {
  return useContext(SupraProviderContext);
};