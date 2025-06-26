'use client';

import { useState } from 'react';

import cn from '@/util/cn';
import { generateUniqueNameFromTimestamp } from '@/util/uniqueName';


import WalletButton from '@/component/WalletButton';
// import { ConnectButton } from '@rainbow-me/rainbowkit';

export default function Home() {

  const [ name ] = useState(generateUniqueNameFromTimestamp);
  // const { getShortAddress } = useWeb3();


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
          {name}
        </div>

        <WalletButton />

      </div>



    </div>


  )


}