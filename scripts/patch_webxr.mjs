#!/usr/bin/env node
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

// Runs inside Godot's browser runtime, before it samples poses. The browser's
// current snapshot is authoritative even if an input-source event was missed.
export function synchronizeInputSources(runtime) {
  if (!runtime.session) return;
  const current = new Set(runtime.session.inputSources);
  for (const source of runtime.input_sources) {
    if (source && !current.has(source)) runtime.removeInputSource(source);
  }
  for (const source of current) {
    if (!runtime.input_sources.includes(source)) runtime.addInputSource(source);
  }
}

export function patchWebXR(source) {
  const marker = '/* Generic-Vr-Platform WebXR input snapshot */';
  if (source.includes(marker)) return source;
  const session = 'GodotWebXR.session=session;';
  const frame = 'GodotWebXR.frame=frame;GodotWebXR.pose=';
  const changes = 'evt.added.forEach(GodotWebXR.addInputSource);evt.removed.forEach(GodotWebXR.removeInputSource)';
  for (const anchor of [session, frame, changes]) {
    if (source.split(anchor).length !== 2) {
      throw new Error('WebXR export template changed: expected one session setup, input handler, and XR frame callback');
    }
  }
  return source.replace(session, `${session}${marker}GodotWebXR.syncInputSources=(${synchronizeInputSources.toString()}).bind(null,GodotWebXR);GodotWebXR.syncInputSources();`)
    .replace(frame, 'GodotWebXR.syncInputSources();' + frame)
    // Old and replacement hands share slot 0/1. Removing the old source
    // after adding its replacement clears the new source out of that slot.
    .replace(changes, 'evt.removed.forEach(GodotWebXR.removeInputSource);evt.added.forEach(GodotWebXR.addInputSource)');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = process.argv[2];
  if (!path) throw new Error('Usage: node scripts/patch_webxr.mjs build/web/index.js');
  await writeFile(path, patchWebXR(await readFile(path, 'utf8')));
}
