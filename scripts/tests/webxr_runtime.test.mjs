import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { patchWebXR, synchronizeInputSources } from '../patch_webxr.mjs';

test('template patch is idempotent and rejects an unknown engine layout', () => {
  const source = 'GodotWebXR.session=session; GodotWebXR.frame=frame;GodotWebXR.pose=pose; evt.added.forEach(GodotWebXR.addInputSource);evt.removed.forEach(GodotWebXR.removeInputSource)';
  const patched = patchWebXR(source);
  assert.equal(patchWebXR(patched), patched);
  assert.throws(() => patchWebXR('unknown template'), /template changed/);
  assert.throws(() => patchWebXR(source + source), /template changed/);
});

test('snapshot replaces stale sources, restores missing slots, and leaves registered sources alone', () => {
  const left = {}, right = {}, stale = {};
  const calls = [];
  const runtime = { session: { inputSources: [left, right] }, input_sources: [stale, right],
    addInputSource(source) { calls.push(['add', source]); this.input_sources[0] = source; },
    removeInputSource(source) { calls.push(['remove', source]); this.input_sources[0] = null; } };
  synchronizeInputSources(runtime);
  assert.deepEqual(calls, [['remove', stale], ['add', left]]);
  calls.length = 0;
  synchronizeInputSources(runtime);
  assert.deepEqual(calls, []);
  runtime.input_sources[0] = null;
  synchronizeInputSources(runtime);
  assert.deepEqual(calls, [['add', left]]);
});

class Session extends EventTarget {
  constructor(sources) { super(); this.inputSources = sources; this.frames = []; }
  requestAnimationFrame(callback) { this.frames.push(callback); return this.frames.length; }
  frame() {
    const frame = { getViewerPose: () => ({ views: [{}, {}] }) };
    this.frames.splice(0).forEach(callback => callback(0, frame));
  }
  end() { this.frames.length = 0; this.dispatchEvent(new Event('end')); return Promise.resolve(); }
  change(added, removed = []) {
    this.inputSources = this.inputSources.filter(source => !removed.includes(source)).concat(added);
    this.dispatchEvent(Object.assign(new Event('inputsourceschange'), { added, removed }));
  }
}

function section(source, start, end) {
  const begin = source.indexOf(start);
  const finish = source.indexOf(end, begin + start.length);
  assert.ok(begin >= 0 && finish > begin, `Exported runtime section missing: ${start}`);
  return source.slice(begin, finish);
}

test('actual exported Godot runtime reconnects hands/controllers across sessions and browser resumes without hardware events',
  { skip: !process.env.WEBXR_EXPORTED_JS }, async () => {
    const exported = patchWebXR(await readFile(process.env.WEBXR_EXPORTED_JS, 'utf8'));
    // Execute the real export's WebXR state and lifecycle functions. Leave GL
    // setup pending: this test isolates input registration before pose sampling.
    const code = section(exported, 'var GodotWebXR=', 'function _godot_webxr_is_supported') +
      section(exported, 'var _godot_webxr_initialize=', '_godot_webxr_initialize.sig=') +
      section(exported, 'var _godot_webxr_uninitialize=', '_godot_webxr_uninitialize.sig=');
    let session;
    const context = vm.createContext({
      ENVIRONMENT_IS_PTHREAD: false,
      navigator: { xr: { requestSession: async () => session } },
      MainLoop: { requestAnimationFrame: () => 0 },
      GodotRuntime: { parseString: value => value, get_func: () => () => {} },
      _emscripten_webgl_get_current_context: () => 0,
      GL: { getContext: () => ({ GLctx: { makeXRCompatible: () => new Promise(() => {}) } }) },
    });
    vm.runInContext(code, context);
    const runtime = context.GodotWebXR;
    runtime.pauseResumeMainLoop = () => {};
    const hands = ['left', 'right'].map(handedness => ({ targetRayMode: 'tracked-pointer', handedness, hand: {} }));
    const controllers = ['left', 'right'].map(handedness => ({ targetRayMode: 'tracked-pointer', handedness }));
    const frame = () => { runtime.requestAnimationFrame(() => {}); session.frame(); };
    for (const sources of [hands, hands, controllers, hands]) {
      session = new Session(sources);
      context._godot_webxr_initialize('immersive-vr', 'local-floor', 'hand-tracking', 'local-floor', 0, 0, 0, 0, 0);
      await Promise.resolve();
      assert.equal(runtime.input_sources[0], sources[0]);
      assert.equal(runtime.input_sources[1], sources[1]);
      runtime.space = {};
      // Resume after the engine loses its slots while browser sources stay
      // connected. No inputsourceschange, occlusion, or controller wake event.
      runtime.input_sources.fill(null);
      frame();
      assert.equal(runtime.input_sources[0], sources[0]);
      assert.equal(runtime.input_sources[1], sources[1]);
      const replacement = { targetRayMode: 'tracked-pointer', handedness: 'left' };
      session.change([replacement], [sources[0]]);
      assert.equal(runtime.input_sources[0], replacement, 'removing the old hand cleared its replacement from the shared slot');
      frame();
      assert.equal(runtime.input_sources[0], replacement);
      const silentReplacement = { targetRayMode: 'tracked-pointer', handedness: 'left' };
      session.inputSources = [silentReplacement, sources[1]];
      frame();
      assert.equal(runtime.input_sources[0], silentReplacement);
      session.change([], [silentReplacement]);
      assert.equal(runtime.input_sources[0], null);
      frame();
      assert.equal(runtime.input_sources[0], null, 'removed source was resurrected');
      context._godot_webxr_uninitialize();
      assert.equal(runtime.session, null);
      assert.equal(runtime.input_sources.filter(Boolean).length, 0);
    }
  });
