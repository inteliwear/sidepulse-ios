import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const assets = new URL('../SidePulse/PatternPreviewWeb/', import.meta.url);
let nextFrame, status, pixels;
const context = vm.createContext({TextEncoder, Uint8Array, WebAssembly, atob,
  performance, console, document:{hidden:false,getElementById:()=>({})},
  requestAnimationFrame:callback=>{nextFrame=callback;},
  createDevicePreview:()=>rgb=>{pixels=Array.from(rgb);},
  webkit:{messageHandlers:{preview:{postMessage:message=>{status=message;}}}}});
context.window=context;
for(const file of ['engine.js','sdled-controller.js','preview-playback.js','native-preview.js']) {
  vm.runInContext(fs.readFileSync(new URL(file,assets),'utf8'),context,{filename:file});
}
const source='off\nbrightness 40\n#FF00FF 500ms pulse\n';
let settings={source,count:2,restart:0,autoRestart:false,active:true};
await context.configurePreview(settings);
assert.match(status,/Playing preview/);
for(let t=0;t<=250;t+=10) nextFrame(t);
assert.ok(Math.max(...pixels)>20 && Math.max(...pixels)<=40);
for(let t=260;t<=1000;t+=10) nextFrame(t);
assert.match(status,/Pattern finished/);
await context.configurePreview({...settings,autoRestart:true});
for(let t=1010;t<=2600;t+=10) nextFrame(t);
assert.match(status,/Playing preview/);
await context.configurePreview({...settings,source:'off\n#FF4600 #0066FF 10000ms none\nrepeat\n',count:8,restart:1});
for(let t=2700;t<=2900;t+=10) nextFrame(t);
assert.equal(pixels.length,24);
assert.ok(Math.max(...pixels)>0);
await context.configurePreview({...settings,source:'bad command',restart:2});
assert.match(status,/Preview unavailable/);
assert.match(status,/line 1/);
await context.configurePreview({...settings,source:'x'.repeat(513),restart:3});
assert.match(status,/too long/);
await context.configurePreview({...settings,source:'off\n#FF0000 #0000FF 500ms cosine\n',restart:4});
nextFrame(3000); nextFrame(3010);
const before=[...pixels];
await context.configurePreview({...settings,source:'off\n#FF0000 #0000FF 500ms cosine\n',restart:4,active:false});
nextFrame(4000); nextFrame(5000);
assert.deepEqual(pixels,before);
console.log('Offline iOS engine: brightness, completion, delayed restart, Pro, parse errors, limits, and background pause passed.');
