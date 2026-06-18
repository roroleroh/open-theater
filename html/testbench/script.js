const container = document.getElementById('container');
const video = document.getElementById('player');
const urlInput = document.getElementById('urlInput');
const typeSelect = document.getElementById('typeSelect');
const status = document.getElementById('status');
const logEl = document.getElementById('log');

let hls = null;

function postNui(endpoint, body) {
    fetch(`https://${GetParentResourceName()}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {})
    });
}

function log(message) {
    const line = document.createElement('div');
    line.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
    logEl.prepend(line);
    postNui('log', { message });
}

function setStatus(text) {
    status.textContent = `Status: ${text}`;
}

function teardownHls() {
    if (hls) {
        hls.destroy();
        hls = null;
    }
}

window.addEventListener('message', (event) => {
    if (event.data && event.data.type === 'open') {
        container.classList.remove('hidden');
        setStatus('idle');
    }
});

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') closeTestBench();
});

document.getElementById('closeBtn').addEventListener('click', closeTestBench);

function closeTestBench() {
    teardownHls();
    video.pause();
    video.removeAttribute('src');
    container.classList.add('hidden');
    postNui('close');
}

document.getElementById('loadBtn').addEventListener('click', () => {
    const url = urlInput.value.trim();
    const type = typeSelect.value;

    if (!url) {
        setStatus('enter a URL first');
        return;
    }

    teardownHls();
    video.removeAttribute('src');
    video.load();
    setStatus('loading...');
    log(`Loading (${type}): ${url}`);

    if (type === 'hls') {
        if (Hls.isSupported()) {
            hls = new Hls();
            hls.loadSource(url);
            hls.attachMedia(video);

            hls.on(Hls.Events.MANIFEST_PARSED, () => {
                setStatus('manifest parsed, playing');
                video.play().catch((err) => log(`play() error: ${err.message}`));
            });

            hls.on(Hls.Events.ERROR, (_event, data) => {
                setStatus(`HLS error: ${data.type} / ${data.details}`);
                log(`HLS ERROR: type=${data.type} details=${data.details} fatal=${data.fatal}`);
            });
        } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
            video.src = url;
            video.play();
            setStatus('playing (native HLS)');
        } else {
            setStatus('HLS not supported by this browser engine');
            log('Hls.js reports isSupported() = false');
        }
    } else {
        video.src = url;
        video.play()
            .then(() => {
                setStatus('playing');
                log('playback started');
            })
            .catch((err) => {
                setStatus(`play() rejected: ${err.message}`);
                log(`play() error: ${err.message}`);
            });
    }
});

video.addEventListener('error', () => {
    const err = video.error;
    const codes = {
        1: 'MEDIA_ERR_ABORTED',
        2: 'MEDIA_ERR_NETWORK',
        3: 'MEDIA_ERR_DECODE',
        4: 'MEDIA_ERR_SRC_NOT_SUPPORTED'
    };
    const msg = err ? (codes[err.code] || `code ${err.code}`) : 'unknown error';
    setStatus(`video error: ${msg}`);
    log(`VIDEO ERROR: ${msg}`);
});

video.addEventListener('playing', () => {
    setStatus(`playing (${video.videoWidth}x${video.videoHeight})`);
});
