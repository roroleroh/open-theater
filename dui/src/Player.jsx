import React, { useRef, useState, useCallback } from 'react';
import ReactPlayer from 'react-player';
import useNuiMessage from './useNuiMessage';
import report from './report';

// Flip to false to hide the on-screen debug HUD. While true, the DUI overlays a
// small event log (messages received, player ready/start/error) so playback
// problems are visible directly on the projected screen — DUI has no console.
const DEBUG = true;

export default function Player() {
    const playerRef = useRef(null);
    const pendingSeek = useRef(0);
    const ready = useRef(false);

    const [url, setUrl] = useState('');
    const [playing, setPlaying] = useState(false);
    const [volume, setVolume] = useState(0);
    const [log, setLog] = useState([]);

    const pushLog = useCallback((line) => {
        report(line); // mirror to the F8 console via the client
        if (!DEBUG) return;
        const stamp = new Date().toISOString().slice(11, 19);
        setLog((prev) => [...prev.slice(-9), `${stamp}  ${line}`]);
    }, []);

    const onPlay = useCallback((msg) => {
        const seek = Number(msg.timestamp) || 0;
        pushLog(`msg play: ${String(msg.url).slice(0, 60)}`);
        if (msg.url && msg.url !== url) {
            ready.current = false;
            pendingSeek.current = seek;
            setUrl(msg.url);
            setPlaying(true);
        } else {
            if (ready.current && playerRef.current && seek > 0) {
                playerRef.current.seekTo(seek, 'seconds');
            } else {
                pendingSeek.current = seek;
            }
            setPlaying(true);
        }
    }, [url, pushLog]);

    const onPause = useCallback(() => setPlaying(false), []);

    const onStop = useCallback(() => {
        pushLog('msg stop');
        ready.current = false;
        pendingSeek.current = 0;
        setPlaying(false);
        setUrl('');
    }, [pushLog]);

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
        pushLog('onReady');
        if (pendingSeek.current > 0 && playerRef.current) {
            playerRef.current.seekTo(pendingSeek.current, 'seconds');
            pendingSeek.current = 0;
        }
    }, [pushLog]);

    return (
        <>
            {url ? (
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
                        onStart={() => pushLog('onStart (playback began)')}
                        onPlay={() => pushLog('onPlay')}
                        onPause={() => pushLog('onPause')}
                        onBuffer={() => pushLog('onBuffer')}
                        onError={(e, data) => {
                            let detail = '';
                            try { detail = JSON.stringify(e && e.message ? e.message : (data || e)); } catch (_) { detail = String(e); }
                            pushLog(`onError: ${String(detail).slice(0, 120)}`);
                        }}
                        config={{
                            youtube: {
                                playerVars: {
                                    controls: 0, modestbranding: 1, rel: 0,
                                    iv_load_policy: 3, disablekb: 1, fs: 0, playsinline: 1,
                                    origin: window.location.origin,
                                },
                            },
                            file: { attributes: { playsInline: true, crossOrigin: 'anonymous' } },
                        }}
                    />
                </div>
            ) : null}

            {DEBUG ? (
                <div className="debug-hud">
                    <div className="debug-state">
                        url:{url ? 'set' : 'none'} | playing:{String(playing)} | vol:{volume.toFixed(2)} | ready:{String(ready.current)} | Hls:{String(typeof window !== 'undefined' && !!window.Hls)}
                    </div>
                    {log.map((line, i) => <div key={i}>{line}</div>)}
                </div>
            ) : null}
        </>
    );
}
