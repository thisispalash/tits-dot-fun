import type { Metadata } from 'next';
import { Sour_Gummy } from 'next/font/google';
import './globals.css';

import cn from '@/util/cn';

import AppProvider from '@/context/AppProvider';

const sourGummy = Sour_Gummy({
  variable: '--font-default',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: 'tits dot [dot] fun',
  description: '',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={cn(
          sourGummy.variable,
          'w-2/3 lg:w-1/2 mx-auto',
          'h-screen min-h-screen',
          'items-center justify-center',
          'bg-background text-foreground',
          'antialiased font-default',
        )}
      >
        <AppProvider>
          {children}
        </AppProvider>
      </body>
    </html>
  );
}
