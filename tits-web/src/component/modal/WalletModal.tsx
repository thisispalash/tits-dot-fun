'use client';

import { useEffect, useState } from 'react';

import cn from '@/util/cn';

import { useSupra } from '@/context/SupraProvider';
import { useWeb3 } from '@/context/Web3Providers';

import BaseModal from './base';

interface WalletModalProps {
  isOpen: boolean;
  onClose: () => void;
}

function SupraBody() {
  
  const { hasStarkey, getPoolTokenBalance, getSupraBalance, connect } = useSupra();
  const { address } = useWeb3();

  if (!hasStarkey) {
    return (
      <div className={cn(
        'flex flex-col gap-4',
      )}>
        <div className={cn(
          'flex flex-row gap-2'
        )}>
          <span className="">Address:</span>
        </div>
      </div>
    )
  }

  return <></>;

}

function FlowBody() {

  return (
    <div className={cn(
      'flex flex-col gap-4',
    )}>

    </div>
  );
}

export default function WalletModal({ isOpen, onClose }: WalletModalProps) {

  const [ title, setTitle ] = useState('');

  const { getShortAddress, chain } = useWeb3();

  useEffect(() => {

    if (chain === 'flow') {
      setTitle('Go with the Flow?');
    } else if (chain === 'supra') {
      setTitle('Paper Trading on Supra');
    }

  }, [])

  return (
    <BaseModal isOpen={isOpen} onClose={onClose} title={title}>
      <div className={cn(
        'flex flex-col gap-4',
      )}>

        {
          {
            'flow': <FlowBody />,
            'supra': <SupraBody />,
          }[chain!] || <SupraBody />
        }



      </div>
    </BaseModal>
  )
}