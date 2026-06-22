import { useEffect } from 'react';
import { useRadio } from '../hooks/useRadio';
import { Mic, Radio } from 'lucide-react';

function App() {
  // Initialize radio and WebRTC listeners
  const { isTransmitting, isLive } = useRadio();

  useEffect(() => {
    console.log('CAD Radio Station UI Loaded');
  }, []);

  return (
    <>
      {isTransmitting && (
        <div className="fixed top-10 left-1/2 -translate-x-1/2 px-6 py-3 bg-red-600/90 text-white rounded-full shadow-lg border border-red-500/50 flex items-center justify-around gap-3 animate-pulse">
          <div className="w-3 h-3 bg-white rounded-full animate-ping" />
          <Mic size={20} /> <span className="font-bold tracking-widest text-sm"> BROADCASTING</span>
        </div>
      )}

      {isLive && !isTransmitting && (
        <div className="fixed top-10 right-10 px-4 py-2 bg-red-600/80 text-white rounded-md shadow-md border border-red-500/30 flex items-center gap-2 animate-pulse">
          <Radio size={18} className="animate-bounce" />
          <span className="font-bold tracking-tighter text-xs">LIVE</span>
        </div>
      )}
    </>
  );
}

export default App;