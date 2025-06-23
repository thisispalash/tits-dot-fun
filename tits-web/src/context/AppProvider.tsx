'use client';

import { createContext, useContext } from 'react';

interface AppProviderContextType {
  getChart: () => React.ReactNode;
}

const AppProviderContext = createContext<AppProviderContextType | null>(null);


export default function AppProvider({ children }: { children: React.ReactNode }) {

  const getChart = () => {
    return <div>Chart</div>;
  };

  return (
    <AppProviderContext.Provider 
      value={{
        getChart,
      }}
    >
      {children}
    </AppProviderContext.Provider>
  );
}


export const useApp = () => {
  return useContext(AppProviderContext);
};