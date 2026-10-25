import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source = (await readFile(new URL('../../Godot/avatar/avatar_webgl_capture.gd',import.meta.url),'utf8')).split('const INSTALL := """\n')[1].split('\n"""')[0];
test('WebGL capture preserves return values, exceptions, inherited hooks and restores prototypes',()=>{
 class GL {
  compileShader(value){return `${this.tag}:${value}`;}
  linkProgram(value){if(value==='bad')throw new TypeError('bad program');return 7;}
  getShaderParameter(_shader,pname){return pname;}
  getProgramParameter(_program,pname){return pname;}
 }
 class GL2 extends GL {}
 let clock=0;
 const context=vm.createContext({WebGLRenderingContext:GL,WebGL2RenderingContext:GL2,performance:{now:()=>clock+=3},document:{visibilityState:'visible'}});
 const original=GL.prototype.compileShader;
 assert.equal(vm.runInContext(source,context),true);
 const gl=new GL2();gl.tag='ctx';
 assert.equal(gl.compileShader('shader'),'ctx:shader');
 assert.equal(gl.linkProgram('good'),7);
 assert.throws(()=>gl.linkProgram('bad'),TypeError);
 gl.getProgramParameter('program',0); // An unrelated query must not count.
 gl.getProgramParameter('program',35714);
 let report=JSON.parse(context.__vrAvatarRenderCapture.snapshot());
 assert.equal(report.methods.compileShader.calls,1); // No double-counting inherited methods.
 assert.equal(report.methods.linkProgram.calls,2);
 assert.equal(report.methods.getProgramParameter.calls,1);
 for(let i=0;i<70;i++)gl.compileShader('shader');
 report=JSON.parse(context.__vrAvatarRenderCapture.snapshot());
 assert.equal(report.slow_calls.length,40);
 assert.equal(report.slow_calls[0].visibility,'visible');
 context.__vrAvatarRenderCapture.stop();
 assert.equal(GL.prototype.compileShader,original);
 assert.equal(Object.hasOwn(GL2.prototype,'compileShader'),false);
 assert.equal(gl.compileShader('restored'),'ctx:restored');
 assert.equal(JSON.parse(context.__vrAvatarRenderCapture.snapshot()).methods.compileShader.calls,71);
});
