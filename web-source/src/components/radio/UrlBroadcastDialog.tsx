import { useState } from 'react';
import { motion } from 'framer-motion';
import { Link2, X } from 'lucide-react';

interface UrlBroadcastDialogProps {
  onSubmit: (url: string) => void;
  onCancel: () => void;
}

// Link prompt for the URL broadcast mode.
function UrlBroadcastDialog({ onSubmit, onCancel }: UrlBroadcastDialogProps) {
  const [url, setUrl] = useState('');

  const submit = () => {
    const trimmed = url.trim();
    if (trimmed !== '') onSubmit(trimmed);
  };

  return (
    <div className="absolute inset-0 z-10 flex items-center justify-center bg-black/60 p-4">
      <motion.div
        initial={{ scale: 0.92, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        exit={{ scale: 0.92, opacity: 0 }}
        className="w-full max-w-sm rounded-xl border border-white/10 bg-card p-5 shadow-2xl"
      >
        <div className="mb-3 flex items-center justify-between">
          <div className="flex items-center gap-2 text-white">
            <Link2 size={18} className="text-amber-400" />
            <h3 className="font-display text-lg font-semibold">Broadcast a Link</h3>
          </div>
          <button
            onClick={onCancel}
            className="rounded-md p-1 text-white/60 transition hover:bg-white/10 hover:text-white"
            aria-label="Cancel"
          >
            <X size={18} />
          </button>
        </div>

        <p className="mb-2 text-xs text-white/50">
          Paste a direct audio stream or a media link
        </p>

        <input
          autoFocus
          type="text"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') submit();
          }}
          placeholder="https://..."
          className="w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none transition focus:border-primary"
        />

        <div className="mt-4 flex justify-end gap-2">
          <button
            onClick={onCancel}
            className="rounded-lg px-4 py-2 text-sm font-medium text-white/70 transition hover:bg-white/10"
          >
            Cancel
          </button>
          <button
            onClick={submit}
            disabled={url.trim() === ''}
            className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-semibold text-black transition hover:bg-amber-400 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Broadcast
          </button>
        </div>
      </motion.div>
    </div>
  );
}

export default UrlBroadcastDialog;
