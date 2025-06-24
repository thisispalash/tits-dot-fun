// 'use client';

// import { useState } from 'react';

// import cn from '@/util/cn';
// import { generateUniqueNameFromTimestamp } from '@/util/uniqueName';

// import WalletModal from './modal/WalletModal';

// export default function WalletButton() {

//   const [ isModalOpen, setIsModalOpen ] = useState(false);
//   const [ name, setName ] = useState(generateUniqueNameFromTimestamp);

//   return <>
//     <div
//       onClick={() => setIsModalOpen(true)}
//       className={cn(
//         'px-4 py-2',
//         'flex flex-row gap-2',
//         'border border-foreground rounded-full',
//         'hover:bg-foreground/10 cursor-pointer',
//         'items-center justify-center',
//       )}
//     >
//       {name}
//     </div>
//     <WalletModal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} />
//   </>;
// }

'use client';

export default function WalletButton() {

  return (
    // @ts-expect-error msg
    <appkit-button 
      balance='hide'
      label='Trade Now!'
      loadingLabel='Modal Open'
      chainStatus='icon'
    />
  );

}