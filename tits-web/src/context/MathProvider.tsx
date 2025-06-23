'use client';

import { createContext, useContext } from 'react';

interface MathProviderContextType {
  getChart: () => React.ReactNode;
}

const MathProviderContext = createContext<MathProviderContextType | null>(null);


export default function MathProvider({ children }: { children: React.ReactNode }) {

  const getChart = () => {
    return <div>Chart</div>;
  };


  return (
    <MathProviderContext.Provider 
      value={{
        getChart,
      }}
    >
      {children}
    </MathProviderContext.Provider>
  );
}


export const useMath = () => {
  return useContext(MathProviderContext);
};