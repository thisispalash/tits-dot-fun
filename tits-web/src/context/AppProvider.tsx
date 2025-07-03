'use client';

import { createContext, useContext } from 'react';
import { useState, useEffect } from 'react';

interface AppProviderContextType {
  tradeData: any;
  setPoolNetwork: (network: string) => void;
}

const AppProviderContext = createContext<AppProviderContextType | null>(null);


export default function AppProvider({ children }: { children: React.ReactNode }) {

  const [ tradeData, setTradeData ] = useState<any>(null);
  const [ poolNetwork, setPoolNetwork ] = useState<string>('simulate');

  const getTradeData = async () => {
  }

  useEffect(() => {
    getTradeData();
  }, [poolNetwork]);


  return (
    <AppProviderContext.Provider 
      value={{
        tradeData,
        setPoolNetwork,
      }}
    >
      {children}
    </AppProviderContext.Provider>
  );
}


export const useApp = () => {
  return useContext(AppProviderContext);
};