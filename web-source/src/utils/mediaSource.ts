// Classifies a broadcast URL so the player knows how to open it.

export type MediaKind = 'direct' | 'embed';

export interface MediaSource {
  kind: MediaKind;
  /** The original URL, used as-is for direct streams. */
  url: string;
  /** Provider id for embedded sources, null for direct streams. */
  embedId: string | null;
}

// Hosts that serve a player page rather than a playable audio response
const EMBED_HOSTS = ['youtube.com', 'youtu.be', 'youtube-nocookie.com'];

/** Strips the leading `www.`/`m.`/`music.` label so host matching stays simple. */
function baseHost(hostname: string): string {
  return hostname.replace(/^(www|m|music)\./, '').toLowerCase();
}

/** Pulls the provider id out of the supported embed URL shapes. */
function extractEmbedId(url: URL): string | null {
  const host = baseHost(url.hostname);

  if (host === 'youtu.be') {
    return url.pathname.slice(1).split('/')[0] || null;
  }

  const fromQuery = url.searchParams.get('v');
  if (fromQuery) return fromQuery;

  // /embed/<id>, /shorts/<id> and /live/<id> all carry the id as the last segment
  const segments = url.pathname.split('/').filter(Boolean);
  if (segments.length >= 2 && ['embed', 'shorts', 'live', 'v'].includes(segments[0])) {
    return segments[1];
  }

  return null;
}

/** Resolves how a broadcast URL should be played. Unparseable input stays direct. */
export function resolveMediaSource(raw: string): MediaSource {
  const trimmed = raw.trim();

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return { kind: 'direct', url: trimmed, embedId: null };
  }

  if (!EMBED_HOSTS.includes(baseHost(url.hostname))) {
    return { kind: 'direct', url: trimmed, embedId: null };
  }

  const embedId = extractEmbedId(url);
  if (!embedId) return { kind: 'direct', url: trimmed, embedId: null };

  return { kind: 'embed', url: trimmed, embedId };
}
