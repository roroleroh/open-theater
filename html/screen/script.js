const video = document.getElementById('player');
let hls = null;

function teardownHls() {
    if (hls) {
        hls.destroy();
        hls = null;
    }
}

window.addEventListener('message', (event) => {
    const data = event.data;

    if (!data || !data.type) return;

    if (data.type === 'stop') {
        teardownHls();
        video.pause();
        video.removeAttribute('src');
        video.load();
        return;
    }

    if (data.type === 'play') {
        teardownHls();

        if (data.videoType === 'hls') {
            if (Hls.isSupported()) {
                hls = new Hls();
                hls.loadSource(data.url);
                hls.attachMedia(video);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    // Live streams: jump to the live edge rather than honouring seekTo
                    if (hls.liveSyncPosition) {
                        video.currentTime = hls.liveSyncPosition;
                    }
                    video.play();
                });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                // Fallback for engines with native HLS support
                video.src = data.url;
                video.addEventListener('loadedmetadata', () => video.play(), { once: true });
            }
        } else {
            // Direct file (mp4/webm) - VOD sync via seekTo
            video.src = data.url;
            video.addEventListener('loadedmetadata', () => {
                if (data.seekTo) video.currentTime = data.seekTo;
                video.play();
            }, { once: true });
        }
    }
});
