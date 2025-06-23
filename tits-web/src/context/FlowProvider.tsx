'use client';

import { createContext, useContext } from 'react';

interface FlowProviderContextType {
  address: string;
  chainId: string;
}

const FlowProviderContext = createContext<FlowProviderContextType | null>(null);


export default function FlowProvider({ children }: { children: React.ReactNode }) {

  return (
    <FlowProviderContext.Provider 
      value={{
        address: '',
        chainId: '',
      }}
    >
      {children}
    </FlowProviderContext.Provider>
  );
}


export const useFlow = () => {
  return useContext(FlowProviderContext);
};