const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const vm = require('node:vm');
const source = readFileSync(resolve(__dirname, '../../Godot/web/webxr_session_bootstrap.js'), 'utf8');
class ChangeEvent extends Event {
    constructor(type, init) { super(type); Object.assign(this, init); }
}
class Session extends EventTarget {
    constructor(sources) { super(); this.inputSources = sources; this.frames = []; }
    requestAnimationFrame(callback) { this.frames.push(callback); }
    frame() { this.frames.splice(0).forEach((callback) => callback()); }
    change(added, removed = []) {
        this.inputSources = this.inputSources.filter((item) => !removed.includes(item));
        this.inputSources.push(...added.filter((item) => !this.inputSources.includes(item)));
        this.dispatchEvent(new ChangeEvent('inputsourceschange', { session: this, added, removed }));
    }
}
function install(requestSession) {
    const xr = { requestSession };
    const context = vm.createContext({ navigator: { xr }, XRInputSourcesChangeEvent: ChangeEvent });
    vm.runInContext(source, context);
    return { xr, context };
}
function engineListener(session) {
    const added = [], removed = [];
    session.addEventListener('inputsourceschange', (event) => {
        added.push(...event.added); removed.push(...event.removed);
    });
    return { added, removed };
}
test('registers already visible hands on both initial entry and re-entry without tracking loss', async () => {
    const hands = [{ handedness: 'left' }, { handedness: 'right' }];
    const { xr } = install(async () => new Session([...hands]));
    for (let entry = 0; entry < 3; entry++) {
        const session = await xr.requestSession('immersive-vr');
        const engine = engineListener(session);
        session.frame();
        assert.deepEqual(engine.added, hands);
        session.frame();
        assert.equal(engine.added.length, 2);
        session.dispatchEvent(new Event('end'));
    }
});
test('does not duplicate real initial input-source additions or replay removed sources', async () => {
    const left = {}, right = {};
    const { xr } = install(async () => new Session([]));
    const session = await xr.requestSession('immersive-vr');
    const engine = engineListener(session);
    session.change([left, right]);
    session.change([], [right]);
    session.frame();
    assert.deepEqual(engine.added, [left, right]);
    assert.deepEqual(engine.removed, [right]);
});
test('replays only missing sources and leaves later hardware events intact', async () => {
    const left = {}, right = {}, replacement = {};
    const { xr } = install(async () => new Session([left]));
    const session = await xr.requestSession('immersive-vr');
    const engine = engineListener(session);
    session.change([right]);
    session.frame();
    assert.deepEqual(engine.added, [right, left]);
    session.change([replacement], [left]);
    assert.deepEqual(engine.added, [right, left, replacement]);
    assert.deepEqual(engine.removed, [left]);
});
test('does not replay into an ended session', async () => {
    const { xr } = install(async () => new Session([{}]));
    const session = await xr.requestSession();
    const engine = engineListener(session);
    session.dispatchEvent(new Event('end'));
    session.frame();
    assert.equal(engine.added.length, 0);
});
test('preserves request receiver, arguments, rejection and idempotent installation', async () => {
    const denied = new Error('permission denied');
    let receiver, args;
    const { xr, context } = install(function (...values) { receiver = this; args = values; return Promise.reject(denied); });
    const wrapped = xr.requestSession;
    vm.runInContext(source, context);
    assert.equal(xr.requestSession, wrapped);
    const options = { optionalFeatures: ['hand-tracking'] };
    await assert.rejects(xr.requestSession('immersive-vr', options), (error) => error === denied);
    assert.equal(receiver, xr);
    assert.deepEqual(args, ['immersive-vr', options]);
});
