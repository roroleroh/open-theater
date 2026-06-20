import React from 'react';
import { createRoot } from 'react-dom/client';
import Hls from 'hls.js';
import Player from './Player';
import './style.css';

// Expose hls.js as a global so react-player reuses it instead of fetching
// hls.min.js from a CDN at runtime. This makes .m3u8 / HLS playback work even
// when outbound CDN traffic is restricted — Chromium (FiveM's CEF) has no
// native HLS support, so without this, m3u8 streams silently fail.
if (typeof window !== 'undefined' && !window.Hls) {
    window.Hls = Hls;
}

try {
    console.log('[OpenTheater] DUI ready');
} catch (_) {}

const container = document.getElementById('root');
const root = createRoot(container);
root.render(<Player />);
