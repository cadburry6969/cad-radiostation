// Playback for embed-only sources, which need a provider iframe instead of an audio element.

const API_SRC = 'https://www.youtube.com/iframe_api';
const CONTAINER_ID = 'radio-embed-host';

interface EmbedInstance {
  loadVideoById(videoId: string): void;
  playVideo(): void;
  stopVideo(): void;
  setVolume(volume: number): void;
  destroy(): void;
}

interface EmbedApi {
  Player: new (element: HTMLElement, options: Record<string, unknown>) => EmbedInstance;
}

declare global {
  interface Window {
    YT?: EmbedApi;
    onYouTubeIframeAPIReady?: () => void;
  }
}

let apiPromise: Promise<EmbedApi> | null = null;
let instance: EmbedInstance | null = null;
let ready = false;

/** Desired state, applied once the iframe reports ready. */
let pendingId: string | null = null;
let volume = 0.5;

/** Loads the provider script once and resolves when its API is usable. */
function loadApi(): Promise<EmbedApi> {
  if (apiPromise) return apiPromise;

  apiPromise = new Promise<EmbedApi>((resolve, reject) => {
    if (window.YT?.Player) {
      resolve(window.YT);
      return;
    }

    const script = document.createElement('script');
    script.src = API_SRC;
    script.async = true;
    script.onerror = () => reject(new Error('embed api unavailable'));
    window.onYouTubeIframeAPIReady = () => {
      if (window.YT) resolve(window.YT);
      else reject(new Error('embed api unavailable'));
    };
    document.head.appendChild(script);
  });

  return apiPromise;
}

/** Off-screen host element. It must stay rendered, as display:none blocks playback. */
function ensureContainer(): HTMLElement {
  const existing = document.getElementById(CONTAINER_ID);
  if (existing) return existing;

  const container = document.createElement('div');
  container.id = CONTAINER_ID;
  container.style.cssText =
    'position:fixed;top:0;left:0;width:1px;height:1px;opacity:0;pointer-events:none;';
  document.body.appendChild(container);
  return container;
}

export const embedPlayer = {
  /** Starts playback of an embed id, reusing the iframe across calls. */
  async play(embedId: string, initialVolume: number): Promise<void> {
    volume = initialVolume;
    pendingId = embedId;

    const api = await loadApi();

    // A newer call may have replaced the request while the API was loading
    if (pendingId !== embedId) return;

    if (instance && ready) {
      instance.loadVideoById(embedId);
      instance.setVolume(volume * 100);
      return;
    }

    if (instance) return;

    instance = new api.Player(ensureContainer(), {
      videoId: embedId,
      playerVars: { autoplay: 1, controls: 0, disablekb: 1, playsinline: 1 },
      events: {
        onReady: () => {
          ready = true;
          if (!instance) return;
          if (pendingId && pendingId !== embedId) instance.loadVideoById(pendingId);
          instance.setVolume(volume * 100);
          instance.playVideo();
        },
      },
    });
  },

  /** Stops playback and clears any queued request. */
  stop(): void {
    pendingId = null;
    if (instance && ready) instance.stopVideo();
  },

  /** Applies a 0-1 volume to the iframe's 0-100 scale. */
  setVolume(next: number): void {
    volume = next;
    if (instance && ready) instance.setVolume(volume * 100);
  },
};
