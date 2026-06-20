import React from 'react';
import { createRoot } from 'react-dom/client';
import Hls from 'hls.js';
import Player from './Player';
import report from './report';
import './style.css';

// Expose hls.js as a global so react-player reuses it instead of fetching
// hls.min.js from a CDN at runtime. Chromium (FiveM's CEF) has no native HLS,
// so without this, .m3u8 streams silently fail.
if (typeof window !== 'undefined' && !window.Hls) {
    window.Hls = Hls;
}

// Surface any uncaught DUI-side error in the F8 console (via the client).
window.addEventListener('error', (e) => {
    report('JS error: ' + (e && e.message ? e.message : String(e)));
});
window.addEventListener('unhandledrejection', (e) => {
    const r = e && e.reason;
    report('promise rejection: ' + (r && r.message ? r.message : String(r)));
});

report('DUI booted. origin=' + window.location.origin + ' hls=' + (!!window.Hls));

const container = document.getElementById('root');
const root = createRoot(container);
root.render(<Player />);
