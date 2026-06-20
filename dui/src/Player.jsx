import React, { useRef, useState, useCallback } from 'react';
import ReactPlayer from 'react-player';
import useNuiMessage from './useNuiMessage';

// The projected cinema player. State is driven entirely by DUI messages from
// Lua (play / pause / stop / seek / volume). Playback position is
// server-authoritative: a 'play' carries the current timestamp so late joiners
// land at the right second.
//
// Volume is driven by the client's proximity loop (0 = silent, 1 = full), so
// the screen gets louder as the player walks toward it. Starting at volume 0
// also keeps autoplay happy in CEF (a silent autostart is always allowed),
// then the proximity loop fades sound in.
export default function Player() {
    const playerRef = useRef(null);
    const pendingSeek = useRef(0);
    const ready = useRef(false);

    const [url, setUrl] = useState('');
    const [playing, setPlaying] = useState(false);
    const [volume, setVolume] = useState(0);

    const onPlay = useCallback((msg) => {
        const seek = Number(msg.timestamp) || 0;
        if (msg.url && msg.url !== url) {
            // New media — mount it; the seek is applied once it's ready.
            ready.current = false;
            pendingSeek.current = seek;
            setUrl(msg.url);
            setPlaying(true);
        } else {
            // Same media (resume / re-sync) — seek directly when possible.
            if (ready.current && playerRef.current && seek > 0) {
                playerRef.current.seekTo(seek, 'seconds');
            } else {
                pendingSeek.current = seek;
            }
            setPlaying(true);
        }
    }, [url]);

    const onPause = useCallback(() => setPlaying(false), []);

    const onStop = useCallback(() => {
        ready.current = false;
        pendingSeek.current = 0;
        setPlaying(false);
        setUrl('');
    }, []);

    const onSeek = useCallback((msg) => {
        const seek = Number(msg.timestamp) || 0;
        if (ready.current && playerRef.current) {
            playerRef.current.seekTo(seek, 'seconds');
        } else {
            pendingSeek.current = seek;
        }
    }, []);

    const onVolume = useCallback((msg) => {
        let v = Number(msg.volume);
        if (!isFinite(v)) v = 0;
        setVolume(Math.max(0, Math.min(1, v)));
    }, []);

    useNuiMessage('play', onPlay);
    useNuiMessage('pause', onPause);
    useNuiMessage('stop', onStop);
    useNuiMessage('seek', onSeek);
    useNuiMessage('volume', onVolume);

    const handleReady = useCallback(() => {
        ready.current = true;
        if (pendingSeek.current > 0 && playerRef.current) {
            playerRef.current.seekTo(pendingSeek.current, 'seconds');
            pendingSeek.current = 0;
        }
    }, []);

    if (!url) return null;

    return (
        <div className="player-wrapper">
            <ReactPlayer
                ref={playerRef}
                className="react-player"
                url={url}
                playing={playing}
                controls={false}
                loop
                muted={false}
                volume={volume}
                width="100%"
                height="100%"
                onReady={handleReady}
                onError={(e) => {
                    try { console.log('[OpenTheater] player error', JSON.stringify(e)); } catch (_) {}
                }}
                config={{
                    youtube: {
                        playerVars: {
                            controls: 0,
                            modestbranding: 1,
                            rel: 0,
                            iv_load_policy: 3,
                            disablekb: 1,
                            fs: 0,
                            playsinline: 1,
                        },
                    },
                    file: {
                        attributes: { playsInline: true },
                    },
                }}
            />
        </div>
    );
}
