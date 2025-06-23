'use client';

import cn from '@/util/cn';


import { useWeb3 } from '@/context/Web3Providers';

export default function WalletButton() {

  const { address, chain } = useWeb3();
  const { createAccount, fundAccount } = useSupra();


}

