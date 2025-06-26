'use client';

/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable react-hooks/exhaustive-deps */

import { createContext, useContext, useEffect, useState } from 'react';
import { SupraAccount, SupraClient, BCS } from 'supra-l1-sdk';

// import { useWeb3 } from './Web3Providers';

interface SupraProviderContextType {
  hasStarkey: boolean;
  fundAccount: () => Promise<void>;
  trade: (
    qty: number, 
    side: 'buy' | 'sell', 
    delay: number, 
    candle_size: '5' | '10' | '15',
  ) => Promise<void>;
  getPoolTokenBalance: () => Promise<number>;
  getSupraBalance: () => Promise<number>;
  connect: () => Promise<void>;
}

const SupraProviderContext = createContext<SupraProviderContextType | null>(null);


export default function SupraProvider({ children }: { children: React.ReactNode }) {

  const [ supraClient, setSupraClient ] = useState<SupraClient | null>(null);
  const [ deployer, setDeployer ] = useState<string | null>(null);

  const [ hasStarkey, setHasStarkey ] = useState<boolean>(false);
  const [ starkeyProvider, setStarkeyProvider ] = useState<any | null>(null);
  const [ account, setAccount ] = useState<SupraAccount | null>(null);

  // const { address, setAddress, setChain } = useWeb3();

  const initializeNewAccount = async () => {
    const _client = await SupraClient.init(
      'https://rpc-testnet.supra.com/'
    );
    const _account = new SupraAccount();
    await fundAccount(_account);
    // setAddress(_account.address().toString());
    setAccount(_account);
    setSupraClient(_client);
  }

  const initializeStarkey = async (_provider: any) => {
    setStarkeyProvider(_provider);
    const chainId = await _provider.getChainId();
    if (chainId === 8) { 
      await _provider.switchNetwork(6); // switch to testnet
    }
    const acc = await _provider.account();
    if (acc.length > 0) {
      // setAddress(acc[0]);
    } else {
      // setAddress(null);
    }

    // setup hooks
    _provider.on('accountsChanged', (accounts: string[]) => {
      if (accounts.length > 0) {
        // setAddress(accounts[0]);
      } else {
        // setAddress(null);
      }
    });

    _provider.on('chainChanged', (chainId: number) => {
      if (chainId === 8) {
        _provider.switchNetwork(6); // switch to testnet
      }
    });

    _provider.on('disconnect', () => {
      // setAddress(null);
    });
  }

  const fundAccount = async (_account?: SupraAccount) => {
    if (!supraClient || !account || !_account) return;
    await supraClient.fundAccountWithFaucet(account ? account.address() : _account.address());
  }

  const getPoolId = async () => {

    const f = hasStarkey? starkeyProvider.invokeViewMethod : supraClient!.invokeViewMethod;
    
    return await f(
      `${deployer}::pool_manager::get_current_active_pool_id`,
      [],
      new TextEncoder().encode(deployer || '')
    );
  }

  const getPoolTokenBalance = async () => {
    // if (!address) return 0;
    const f = hasStarkey? starkeyProvider.getAccountCoinBalance : supraClient!.getAccountCoinBalance;
    return await f(account!.address(), 'PoolToken');
  }

  const getSupraBalance = async () => {
    // if (!address) return 0;
    const f = hasStarkey? starkeyProvider.getAccountSupraCoinBalance : supraClient!.getAccountSupraCoinBalance;
    return await f(account!.address());
  }

  const connect = async () => {
    if (hasStarkey) {
      await starkeyProvider.connect();
      const acc = await starkeyProvider.account();
      if (acc.length > 0) {
        // setAddress(acc[0]);
      } else {
        // setAddress(null);
      }
    } else {
      await initializeNewAccount();
    }
  }

  useEffect(() => {
    // setChain('supra');

    const _provider = typeof window !== "undefined" && (window as any)?.starkey?.supra;
    const _deployer = process.env.NEXT_PUBLIC_SUPRA_TITS_DEPLOYER;

    setDeployer(_deployer ?? null);

    if (_provider) {
      setHasStarkey(true);
      initializeStarkey(_provider);
    } else {
      initializeNewAccount();
    }
  });

  const trade = async (
    qty: number, 
    side: 'buy' | 'sell', 
    delay: number, 
    candle_size: '5' | '10' | '15',
  ) => {
    if (!supraClient || !account) return;

    const poolId = await getPoolId();

    const rawTx = await supraClient.createRawTxObject(
      account.address(),
      (await supraClient.getAccountInfo(account.address())).sequence_number,
      process.env.NEXT_PUBLIC_SUPRA_TITS_DEPLOYER || '',
      'pool_manager',
      'trade',
      [],
      [
        new TextEncoder().encode(process.env.NEXT_PUBLIC_SUPRA_TITS_DEPLOYER || ''),
        BCS.bcsSerializeUint64(poolId),
        BCS.bcsSerializeUint64(qty),
        BCS.bcsSerializeBool(side === 'buy'),
        BCS.bcsSerializeUint64(delay),
        BCS.bcsSerializeUint64(Number(candle_size)),
      ]
    );

    console.log(rawTx);
  }

  return (
    <SupraProviderContext.Provider 
      value={{
        hasStarkey,
        fundAccount,
        trade,
        getPoolTokenBalance,
        getSupraBalance,
        connect,
      }}
    >
      {children}
    </SupraProviderContext.Provider>
  );
}


export const useSupra = () => {
  const context = useContext(SupraProviderContext);
  if (!context) {
    throw new Error('useSupra must be used within a SupraProvider');
  }
  return context;
};