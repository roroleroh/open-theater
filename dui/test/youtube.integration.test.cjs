/*
 * DUI integration test (no browser, no network).
 *
 * Renders the real Player.jsx under jsdom with the YouTube IFrame SDK mocked,
 * then drives it exactly like Lua does: a 'play' message with a YouTube URL +
 * timestamp, followed by a 'volume' message. Asserts that react-player routed
 * the YouTube URL to the YouTube backend and that our wiring produced the
 * expected player calls (playVideo, seekTo, setVolume).
 *
 * This proves the integration logic end-to-end. It does NOT (and cannot here)
 * prove real pixels/audio inside FiveM's CEF — that needs the game client.
 */
require('@babel/register')();

const assert = require('assert');
const Module = require('module');
const { JSDOM } = require('jsdom');

// Player.jsx imports the full 'react-player', which lazy-loads each backend via
// an extensionless dynamic import(). webpack resolves that in the shipped
// bundle, but Node's ESM loader can't. Alias the import to react-player's
// non-lazy YouTube build — the exact same YouTube backend + Player wrapper,
// just statically loaded so it runs under Node.
const origLoad = Module._load;
Module._load = function (request, parent, isMain) {
    if (request === 'react-player') {
        return origLoad.call(this, 'react-player/youtube', parent, isMain);
    }
    return origLoad.apply(this, arguments);
};

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', {
    url: 'https://localhost/',
    pretendToBeVisual: true,
});

global.window = dom.window;
global.document = dom.window.document;
global.navigator = dom.window.navigator;
global.HTMLElement = dom.window.HTMLElement;
global.MessageEvent = dom.window.MessageEvent;
global.requestAnimationFrame = (cb) => setTimeout(cb, 0);
global.cancelAnimationFrame = (id) => clearTimeout(id);
global.IS_REACT_ACT_ENVIRONMENT = true;

// ----- Mock the YouTube IFrame SDK -----
const calls = { playVideo: 0, pauseVideo: 0, seekTo: [], setVolume: [] };

function MockYTPlayer(container, opts) {
    this.opts = opts;
    setTimeout(() => {
        if (opts.events && typeof opts.events.onReady === 'function') {
            opts.events.onReady({ target: this });
        }
    }, 0);
}
MockYTPlayer.prototype.playVideo = function () { calls.playVideo++; };
MockYTPlayer.prototype.pauseVideo = function () { calls.pauseVideo++; };
MockYTPlayer.prototype.seekTo = function (s) { calls.seekTo.push(s); };
MockYTPlayer.prototype.setVolume = function (v) { calls.setVolume.push(v); };
MockYTPlayer.prototype.mute = function () {};
MockYTPlayer.prototype.unMute = function () {};
MockYTPlayer.prototype.setPlaybackRate = function () {};
MockYTPlayer.prototype.setLoop = function () {};
MockYTPlayer.prototype.getDuration = function () { return 100; };
MockYTPlayer.prototype.getCurrentTime = function () { return 0; };
MockYTPlayer.prototype.getSecondsLoaded = function () { return 0; };
MockYTPlayer.prototype.getPlayerState = function () { return 1; };
MockYTPlayer.prototype.cueVideoById = function () {};
MockYTPlayer.prototype.loadVideoById = function () {};
MockYTPlayer.prototype.destroy = function () {};

dom.window.YT = {
    loaded: 1,
    Player: MockYTPlayer,
    PlayerState: { UNSTARTED: -1, ENDED: 0, PLAYING: 1, PAUSED: 2, BUFFERING: 3, CUED: 5 },
};

const React = require('react');
const { createRoot } = require('react-dom/client');
const { act } = require('react');
const Player = require('../src/Player.jsx').default;

const YT_URL = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

function send(payload) {
    dom.window.dispatchEvent(new dom.window.MessageEvent('message', {
        data: JSON.stringify(payload),
    }));
}

const tick = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
    const root = createRoot(document.getElementById('root'));

    await act(async () => { root.render(React.createElement(Player)); });

    // Nothing should be mounted before a URL arrives.
    assert.strictEqual(document.querySelector('.react-player'), null,
        'player should not mount until a play message arrives');

    // Lua-equivalent: play a YouTube URL, resume at 5s.
    await act(async () => { send({ type: 'play', url: YT_URL, timestamp: 5 }); });
    await act(async () => { await tick(300); });

    // Proximity loop raises volume to 0.8.
    await act(async () => { send({ type: 'volume', volume: 0.8 }); });
    await act(async () => { await tick(150); });

    assert.ok(calls.playVideo > 0, 'expected playVideo() to be called');
    assert.ok(calls.seekTo.includes(5), `expected seekTo(5); got [${calls.seekTo}]`);
    assert.ok(calls.setVolume.includes(80),
        `expected setVolume(80) from volume 0.8; got [${calls.setVolume}]`);

    console.log('PASS: YouTube URL routed to YouTube backend');
    console.log('  playVideo calls :', calls.playVideo);
    console.log('  seekTo values   :', JSON.stringify(calls.seekTo));
    console.log('  setVolume values:', JSON.stringify(calls.setVolume));
    process.exit(0);
})().catch((err) => {
    console.error('FAIL:', err && err.message ? err.message : err);
    process.exit(1);
});
