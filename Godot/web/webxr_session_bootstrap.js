/* Godot 4.7's WebXR listener misses input sources already present at session
 * creation. Replay only those missing the initial inputsourceschange event,
 * once the engine has installed its listener and the first XR frame arrives. */
(() => {
    const xr = globalThis.navigator?.xr;
    if (!xr || xr.__vrPlatformInputBootstrap) return;
    const requestSession = xr.requestSession;
    xr.requestSession = function (...args) {
        return Reflect.apply(requestSession, this, args).then((session) => {
            const observed = new Set();
            let ended = false;
            const onChange = (event) => {
                for (const source of event.added) observed.add(source);
                for (const source of event.removed) observed.delete(source);
            };
            session.addEventListener('inputsourceschange', onChange);
            session.addEventListener('end', () => {
                ended = true;
                session.removeEventListener('inputsourceschange', onChange);
            }, { once: true });
            session.requestAnimationFrame(() => {
                if (ended) return;
                const missing = Array.from(session.inputSources).filter((source) => !observed.has(source));
                if (missing.length) {
                    session.dispatchEvent(new XRInputSourcesChangeEvent('inputsourceschange', {
                        session, added: missing, removed: [],
                    }));
                }
            });
            return session;
        });
    };
    Object.defineProperty(xr, '__vrPlatformInputBootstrap', { value: true });
})();
