import type { Metadata } from 'next';
import { Sour_Gummy } from 'next/font/google';
import './globals.css';

import cn from '@/util/cn';

import AppProvider from '@/context/AppProvider';
import Web3Providers from '@/context/Web3Providers';

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
          'container mx-auto p-4',
          'bg-background text-foreground',
          'antialiased font-default',
        )}
      >
        <Web3Providers cookies={null}>
          <AppProvider>
            {children}
          </AppProvider>
        </Web3Providers>
      </body>
    </html>
  );
}
