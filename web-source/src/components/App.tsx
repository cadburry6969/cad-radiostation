import { useEffect } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Mic, Radio } from 'lucide-react';
import { useRadio } from '../hooks/useRadio';
import { useNuiEvent } from '../hooks/useNuiEvent';
import { useRadioStore } from '../store/radio';
import { fetchNui } from '../utils/fetchNui';
import type {
  OpenRadioPayload,
  OpenStationPayload,
  UpdateStatePayload,
} from '../types/radio';
import VehicleRadio from './radio/VehicleRadio';
import StationPanel from './radio/StationPanel';

function App() {
  // Owns the audio element and every WebRTC peer connection.
  const { isTransmitting, isLive } = useRadio();

  const { view, openRadio, openStation, close, setState } = useRadioStore();

  useNuiEvent<OpenRadioPayload>('openRadio', openRadio);
  useNuiEvent<OpenStationPayload>('openStation', openStation);
  useNuiEvent('closeMenu', close);
  useNuiEvent<UpdateStatePayload>('updateRadioState', (data) => setState(data.state));

  // Closing always tells Lua to release NUI focus.
  const handleClose = () => {
    close();
    fetchNui('closeMenu');
  };

  useEffect(() => {
    if (!view) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') handleClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view]);

  return (
    <>
      <AnimatePresence>
        {view && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 flex items-center justify-center"
          >
            {view === 'radio' ? (
              <VehicleRadio onClose={handleClose} />
            ) : (
              <StationPanel onClose={handleClose} />
            )}
          </motion.div>
        )}
      </AnimatePresence>

      {isTransmitting && (
        <div className="fixed left-1/2 top-10 flex -translate-x-1/2 items-center gap-3 rounded-full border border-red-500/50 bg-red-600/90 px-6 py-3 text-white shadow-lg">
          <span className="h-3 w-3 animate-ping rounded-full bg-white" />
          <Mic size={20} />
          <span className="text-sm font-bold tracking-widest">BROADCASTING</span>
        </div>
      )}

      {isLive && !isTransmitting && (
        <div className="fixed right-10 top-10 flex items-center gap-2 rounded-md border border-red-500/30 bg-red-600/80 px-4 py-2 text-white shadow-md">
          <Radio size={18} />
          <span className="text-xs font-bold tracking-tight">LIVE</span>
        </div>
      )}
    </>
  );
}

export default App;
