/* Godot's WebXR listener needs a snapshot of sources already connected when
 * it subscribes. Track delivery per listener, rather than assuming an event
 * seen by this bootstrap was also seen by the engine. */
(() => {
    const xr = globalThis.navigator?.xr;
    if (!xr || xr.__vrPlatformInputBootstrap) return;
    const requestSession = xr.requestSession;
    xr.requestSession = function (...args) {
        return Reflect.apply(requestSession, this, args).then((session) => {
            let ended = false;
            const add = session.addEventListener;
            const remove = session.removeEventListener;
            const listeners = new Map();
            Reflect.apply(add, session, ['end', () => { ended = true; }, { once: true }]);
            session.addEventListener = function (type, listener, options) {
                if (type !== 'inputsourceschange' || !listener) {
                    return Reflect.apply(add, this, [type, listener, options]);
                }
                const capture = typeof options === 'boolean' ? options : !!options?.capture;
                let records = listeners.get(listener);
                if (!records) listeners.set(listener, records = new Map());
                const existing = records.get(capture);
                if (existing && !existing.signal?.aborted) return;
                const record = { observed: new Set(), active: true, signal: options?.signal };
                record.deliver = function (event) {
                    for (const source of event.added) record.observed.add(source);
                    for (const source of event.removed) record.observed.delete(source);
                    if (options?.once) {
                        record.active = false;
                        records.delete(capture);
                        Reflect.apply(remove, session, [type, record.deliver, capture]);
                    }
                    if (typeof listener === 'function') listener.call(session, event);
                    else listener.handleEvent(event);
                };
                records.set(capture, record);
                Reflect.apply(add, this, [type, record.deliver, options]);
                // Schedule after this consumer subscribes, even if session setup
                // took longer than the first XR frame. Do not broadcast to other
                // consumers: they may already have received the real event.
                session.requestAnimationFrame(() => {
                    if (ended || !record.active || options?.signal?.aborted) return;
                    const missing = Array.from(session.inputSources).filter((source) => !record.observed.has(source));
                    if (missing.length) record.deliver(new XRInputSourcesChangeEvent(type, {
                        session, added: missing, removed: [],
                    }));
                });
            };
            session.removeEventListener = function (type, listener, options) {
                const capture = typeof options === 'boolean' ? options : !!options?.capture;
                const records = listeners.get(listener);
                const record = type === 'inputsourceschange' ? records?.get(capture) : null;
                if (record) {
                    record.active = false;
                    records.delete(capture);
                }
                return Reflect.apply(remove, this, [type, record?.deliver || listener, options]);
            };
            return session;
        });
    };
    Object.defineProperty(xr, '__vrPlatformInputBootstrap', { value: true });
})();
