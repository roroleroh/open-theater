import { useEffect } from 'react';

// Subscribe to a DUI message type. Lua sends messages via SendDuiMessage with a
// JSON string body: { type, ...fields }. The matching handler is invoked with
// the full decoded object.
export default function useNuiMessage(type, handler) {
    useEffect(() => {
        const listener = (event) => {
            let data = event.data;
            if (typeof data === 'string') {
                try {
                    data = JSON.parse(data);
                } catch (_) {
                    return;
                }
            }
            if (!data || typeof data !== 'object') return;
            if (data.type !== type) return;
            handler(data);
        };

        window.addEventListener('message', listener);
        return () => window.removeEventListener('message', listener);
    }, [type, handler]);
}
