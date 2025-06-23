'use client';

import cn from '@/util/cn';

interface BaseModalProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
}

export default function BaseModal({ isOpen, onClose, children, title }: BaseModalProps) {
  return (
    <div 
      className={cn(
        'fixed inset-0 bg-foreground/5 p-4',
        'flex items-center justify-center',
        'transition-opacity duration-300 ease-in-out',
        isOpen ? 'opacity-100' : 'opacity-0 pointer-events-none',
      )}
      onClick={onClose}
    >
      <div 
        className="bg-background border border-foreground rounded-lg p-6 max-w-md w-full shadow-2xl shadow-foreground/50 backdrop-blur-sm"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex justify-between items-center mb-6">
          {title && <h2 className="text-xl font-system">{title}</h2>}

          {/* Close button */}
          <button 
            className="absolute top-4 right-6 text-2xl font-system cursor-pointer hover:font-user hover:text-foreground/50 transition-colors"
            onClick={onClose}
          >
            &times;
          </button>
        </div>
        
        <div className="mt-2">
          {children}
        </div>
      </div>

    </div>
  );
}