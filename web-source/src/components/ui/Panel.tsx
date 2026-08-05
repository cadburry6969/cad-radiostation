import type { ReactNode } from 'react';
import { motion } from 'framer-motion';
import { X } from 'lucide-react';

interface PanelProps {
  title: string;
  subtitle?: string;
  icon: ReactNode;
  children: ReactNode;
  footer?: string;
  onClose: () => void;
}

// Shared frame for both interfaces, opaque because backdrop-filter renders black in CEF.
function Panel({ title, subtitle, icon, children, footer, onClose }: PanelProps) {
  return (
    <motion.div
      initial={{ scale: 0.95, y: 10, opacity: 0 }}
      animate={{ scale: 1, y: 0, opacity: 1 }}
      exit={{ scale: 0.95, y: 10, opacity: 0 }}
      transition={{ type: 'spring', stiffness: 300, damping: 26 }}
      className="relative w-[380px] rounded-2xl border border-white/10 bg-background p-5 shadow-2xl"
    >
      <div className="mb-4 flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2 text-white">
          <span className="text-primary">{icon}</span>
          <div className="min-w-0">
            <h1 className="truncate font-display text-xl font-bold tracking-tight">{title}</h1>
            {subtitle && <p className="truncate text-xs text-white/50">{subtitle}</p>}
          </div>
        </div>
        <button
          onClick={onClose}
          className="shrink-0 rounded-md p-1.5 text-white/60 transition hover:bg-white/10 hover:text-white"
          aria-label="Close"
        >
          <X size={18} />
        </button>
      </div>

      {children}

      <p className="mt-4 text-center text-[11px] text-white/30">{footer ?? 'Press ESC to close'}</p>
    </motion.div>
  );
}

export default Panel;
