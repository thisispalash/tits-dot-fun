'use client';

import { useEffect } from 'react';

import cn from '@/util/cn';


import { useSupra } from '@/context/SupraProvider';
import { useWeb3 } from '@/context/Web3Providers';

export default function Home() {

  const { hasStarkey, getPoolTokenBalance, getSupraBalance, connect } = useSupra();
  const { getShortAddress } = useWeb3();

  useEffect(() => {

    if (hasStarkey) {
      getPoolTokenBalance().then(console.log);
      getSupraBalance().then(console.log);
      console.log(getShortAddress());
      connect();
    }
  }, [hasStarkey]);


  return (

    <div className={cn(
      'w-full h-full px-16',
      'flex flex-col gap-4',
      'items-center justify-center',
    )}>

      <div className={cn(
        'w-full',
        'flex flex-row',
        'items-center justify-between',
      )}>

        <div className={cn(
          ''
        )}>
          Faucet
        </div>

        <div className={cn(
          'flex flex-row',
          'items-center justify-between',
        )}>
          {getShortAddress()}
        </div>




      </div>



    </div>


  )


}