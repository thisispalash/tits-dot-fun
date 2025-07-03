'use client';

import cn from '@/util/cn';

import Header from '@/component/Header';
import Chart from '@/component/Chart';
import GameOptions from '@/component/GameOptions';
import TradeButton from '@/component/TradeButton';

export default function Home() {


  return (

    <div className={cn(
      'w-full h-full py-8',
      'flex flex-col gap-8',
      'items-center justify-center'
    )}>

      <Header />

      <Chart />

      <GameOptions />

      <TradeButton />

      {/* <Ticker /> */}


    </div>


  )


}