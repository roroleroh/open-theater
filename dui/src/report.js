// Ship a log line from inside the DUI back to the client Lua, which prints it
// to the F8 console. The DUI is loaded from https://cfx-nui-<resource>/, so
// window.location.host is 'cfx-nui-<resource>' and a fetch to /<callback> on
// that origin routes to the resource's RegisterNUICallback handler.
export default function report(line) {
    try {
        const body = JSON.stringify({ line: String(line) });
        fetch(`https://${window.location.host}/duilog`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body,
        }).catch(() => {});
    } catch (_) {
        /* never let logging throw */
    }
    try { console.log('[OpenTheater DUI]', line); } catch (_) {}
}
