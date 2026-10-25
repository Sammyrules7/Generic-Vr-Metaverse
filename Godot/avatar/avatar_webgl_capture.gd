class_name AvatarWebGLCapture
extends RefCounted
## Observe existing WebGL calls only: no shader sources, readback, flush or finish.
const INSTALL := """
(() => {
 const key = '__vrAvatarRenderCapture';
 if (globalThis[key]) globalThis[key].stop();
 const capture = {active:true, methods:{}, events:[], hooks:[], originals:new WeakMap(), started:performance.now(), base:0};
 const names = ['compileShader','linkProgram','getShaderParameter','getProgramParameter',
  'getUniformLocation','useProgram','texImage2D','texSubImage2D','compressedTexImage2D','bufferData'];
 for (const name of ['WebGLRenderingContext','WebGL2RenderingContext']) {
  const proto = globalThis[name]?.prototype;
  if (!proto) continue;
  for (const method of names) {
   const candidate = proto[method];
   const original = capture.originals.get(candidate) || candidate;
   if (typeof original !== 'function') continue;
   const own = Object.getOwnPropertyDescriptor(proto,method);
   const wrapped = function(...args) {
    if (!capture.active || (method==='getShaderParameter' && args[1]!==35713)
     || (method==='getProgramParameter' && args[1]!==35714)) return Reflect.apply(original,this,args);
    const start = performance.now();
    try { return Reflect.apply(original,this,args); }
    finally {
     const ms = performance.now()-start;
     const stat = capture.methods[method] ||= {calls:0,total_ms:0,max_ms:0};
     stat.calls++; stat.total_ms+=ms; stat.max_ms=Math.max(stat.max_ms,ms);
     if (ms>=2) {
      capture.events.push({at_ms:capture.base+start-capture.started,call:method,ms,visibility:document.visibilityState});
      if (capture.events.length>40) capture.events.shift();
     }
    }
   };
   capture.originals.set(wrapped,original);
   try {
    Object.defineProperty(proto,method,{configurable:true,writable:true,value:wrapped});
    capture.hooks.push({proto,method,wrapped,own});
   } catch (_) {}
  }
 }
 capture.stop = () => {
  capture.active=false;
  for (const hook of capture.hooks) {
   if (hook.proto[hook.method]!==hook.wrapped) continue;
   if (hook.own) Object.defineProperty(hook.proto,hook.method,hook.own);
   else delete hook.proto[hook.method];
  }
  capture.hooks=[];
 };
 capture.snapshot = () => JSON.stringify({methods:capture.methods,slow_calls:capture.events,
  scope:'main-context calls only; zero is inconclusive for worker contexts; CPU wall, not GPU completion',visibility:document.visibilityState});
 globalThis[key]=capture;
 return capture.hooks.length>0;
})();
"""
