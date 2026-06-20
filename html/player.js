// Ares Open Theater — DUI player
// Listens for postMessage from Lua, dispatches to either YouTube IFrame API
// or HTML5 <video> based on URL. Buffers commands until the chosen backend
// is ready.

(function () {
    'use strict';

    const YOUTUBE_API_SRC = 'https://www.youtube.com/iframe_api';

    const state = {
        backend: null,        // 'youtube' | 'mp4'
        url: null,
        timestamp: 0,
        desiredPlay: false,
        ytPlayer: null,       // YT.Player instance once ready
        ytReady: false,
        buffer: [],           // commands received before backend is ready
        mp4El: null,
    };

    // ---------- YouTube IFrame API loader ----------

    function loadYouTubeApi() {
        return new Promise((resolve, reject) => {
            if (window.YT && window.YT.Player) {
                resolve();
                return;
            }

            // Stash the original callback under our own name so we don't
            // collide with any other consumer of the global API.
            const prev = window.onYouTubeIframeAPIReady;
            window.onYouTubeIframeAPIReady = function () {
                if (typeof prev === 'function') prev();
                resolve();
            };

            const tag = document.createElement('script');
            tag.src = YOUTUBE_API_SRC;
            tag.onerror = () => reject(new Error('Failed to load YouTube IFrame API'));
            document.head.appendChild(tag);
        });
    }

    function isYouTubeUrl(url) {
        return typeof url === 'string' && /(?:youtube\.com|youtu\.be)/i.test(url);
    }

    function isMp4Url(url) {
        return typeof url === 'string' && /\.(mp4|m3u8|webm|ogg)(\?|$)/i.test(url);
    }

    function youtubeIdFromUrl(url) {
        if (typeof url !== 'string') return null;
        // Bare 11-char video id.
        if (/^[A-Za-z0-9_-]{11}$/.test(url)) return url;
        try {
            const u = new URL(url);
            if (u.hostname.includes('youtu.be')) {
                return u.pathname.slice(1).split('/')[0] || null;
            }
            const v = u.searchParams.get('v');
            if (v) return v;
            // /shorts/ID, /embed/ID, /live/ID, /v/ID
            const m = u.pathname.match(/\/(?:shorts|embed|live|v)\/([A-Za-z0-9_-]{11})/);
            return m ? m[1] : null;
        } catch (_) {
            return null;
        }
    }

    // ---------- Backend switching ----------

    function teardown() {
        if (state.ytPlayer) {
            try { state.ytPlayer.destroy(); } catch (_) {}
            state.ytPlayer = null;
        }
        if (state.mp4El) {
            state.mp4El.pause();
            state.mp4El.removeAttribute('src');
            state.mp4El.load();
        }
        state.ytReady = false;
        state.backend = null;
        document.getElementById('player').classList.remove('is-active');
        document.getElementById('videoEl').style.display = 'none';
    }

    async function mountYouTube(videoId, autoplay, seekSeconds) {
        teardown();
        await loadYouTubeApi();
        state.backend = 'youtube';
        const host = document.getElementById('player');
        host.innerHTML = '';
        host.classList.add('is-active');

        state.ytPlayer = new YT.Player(host, {
            videoId: videoId,
            playerVars: {
                autoplay: autoplay ? 1 : 0,
                controls: 0,
                modestbranding: 1,
                rel: 0,
                showinfo: 0,
                iv_load_policy: 3,
                disablekb: 1,
                fs: 0,
            },
            events: {
                onReady: (ev) => {
                    state.ytReady = true;
                    if (seekSeconds && seekSeconds > 0) {
                        ev.target.seekTo(seekSeconds, true);
                    }
                    if (autoplay) {
                        ev.target.playVideo();
                    }
                    flushBuffer();
                },
                onStateChange: (ev) => {
                    // YT.PlayerState.ENDED == 0 — loop for cinema use
                    if (ev.data === 0) {
                        ev.target.seekTo(0, true);
                        ev.target.playVideo();
                    }
                },
            },
        });
    }

    function mountMp4(url, autoplay, seekSeconds) {
        teardown();
        state.backend = 'mp4';
        const el = document.getElementById('videoEl');
        el.style.display = 'block';
        el.src = url;
        el.loop = true;
        el.muted = false;
        el.autoplay = autoplay;

        const onReady = () => {
            if (seekSeconds && seekSeconds > 0) {
                el.currentTime = seekSeconds;
            }
            if (autoplay) {
                el.play().catch(() => {});
            }
            flushBuffer();
        };

        if (el.readyState >= 1) {
            onReady();
        } else {
            el.addEventListener('loadedmetadata', onReady, { once: true });
        }
    }

    // ---------- Command dispatch ----------

    function flushBuffer() {
        const pending = state.buffer;
        state.buffer = [];
        for (const cmd of pending) {
            apply(cmd);
        }
    }

    function backendReady() {
        if (state.backend === 'youtube') return state.ytReady;
        if (state.backend === 'mp4') return true;
        return false;
    }

    function bufferOrApply(cmd) {
        // 'play' and 'stop' establish or tear down the backend, so they must
        // always run immediately — they are what *selects* and mounts a
        // backend in the first place. The old code buffered them while
        // state.backend was null, but since the backend is only ever set from
        // inside apply(), the very first play was buffered forever and nothing
        // ever mounted: no video, no audio, no error.
        if (cmd.type === 'play' || cmd.type === 'stop') {
            apply(cmd);
            return;
        }
        // Control commands (pause/seek) need a mounted, ready backend.
        // Buffer them until the backend signals ready; flushBuffer() then
        // replays them in order.
        if (!backendReady()) {
            state.buffer.push(cmd);
            return;
        }
        apply(cmd);
    }

    function apply(cmd) {
        if (!cmd || typeof cmd !== 'object') return;

        switch (cmd.type) {
            case 'play': {
                const url = cmd.url;
                const seek = Number(cmd.timestamp) || 0;
                const changed = url !== state.url;
                state.url = url;
                state.timestamp = seek;

                if (isYouTubeUrl(url)) {
                    const id = youtubeIdFromUrl(url);
                    if (!id) break;
                    if (changed || !state.ytPlayer) {
                        mountYouTube(id, true, seek);
                    } else if (state.ytReady) {
                        state.ytPlayer.seekTo(seek, true);
                        state.ytPlayer.playVideo();
                    }
                } else if (isMp4Url(url)) {
                    if (changed) {
                        mountMp4(url, true, seek);
                    } else {
                        const el = document.getElementById('videoEl');
                        el.currentTime = seek;
                        el.play().catch(() => {});
                    }
                }
                break;
            }

            case 'pause': {
                if (state.backend === 'youtube' && state.ytReady) {
                    state.ytPlayer.pauseVideo();
                } else if (state.backend === 'mp4') {
                    document.getElementById('videoEl').pause();
                }
                break;
            }

            case 'stop': {
                teardown();
                state.url = null;
                state.timestamp = 0;
                break;
            }

            case 'seek': {
                const seek = Number(cmd.timestamp) || 0;
                state.timestamp = seek;
                if (state.backend === 'youtube' && state.ytReady) {
                    state.ytPlayer.seekTo(seek, true);
                } else if (state.backend === 'mp4') {
                    document.getElementById('videoEl').currentTime = seek;
                }
                break;
            }

            default:
                break;
        }
    }

    // ---------- Lua postMessage bridge ----------

    window.addEventListener('message', function (ev) {
        let payload = ev.data;
        if (typeof payload === 'string') {
            try { payload = JSON.parse(payload); } catch (_) { return; }
        }
        if (!payload || typeof payload !== 'object') return;
        bufferOrApply(payload);
    });

    // ---------- Console breadcrumb so you can see the DUI loaded ----------

    try {
        console.log('[OpenTheater] DUI ready');
    } catch (_) {}
})();