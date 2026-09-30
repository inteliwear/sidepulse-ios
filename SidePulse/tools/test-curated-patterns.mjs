// Exercise the actual Swift catalog through the bundled firmware engine.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const app = fileURLToPath(new URL('../SidePulse/', import.meta.url));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'sidepulse-curation-'));
try {
  const main = path.join(temporary, 'main.swift');
  const executable = path.join(temporary, 'catalog');
  fs.writeFileSync(main, 'import Foundation\nFileHandle.standardOutput.write(try JSONEncoder().encode(LibraryPattern.starters))\n');
  execFileSync('swiftc', [path.join(app, 'PatternLibrary.swift'), main, '-o', executable]);
  const patterns = JSON.parse(execFileSync(executable, {encoding:'utf8'}));
  const context = vm.createContext({TextEncoder, Uint8Array, WebAssembly, atob, performance});
  context.window = context;
  for (const file of ['engine.js', 'sdled-controller.js']) {
    vm.runInContext(fs.readFileSync(path.join(app, 'PatternPreviewWeb', file), 'utf8'), context, {filename:file});
  }
  for (const pattern of patterns) {
    const controller = await context.createSdLedController({ledCount:2});
    controller.reset(0);
    assert.equal(controller.parse(pattern.source, 0).ok, true, pattern.name);
    const frames = new Set();
    let peak = 0, asymmetric = false;
    for (let time = 0; time <= 20000; time += 20) {
      const rgb = Array.from(controller.step(time));
      peak = Math.max(peak, ...rgb);
      frames.add(rgb.join());
      asymmetric ||= rgb.slice(0,3).join() !== rgb.slice(3).join();
      if (time > 2000 && ['Aurora','Sunset','Ocean','Candlelight','Spectrum'].includes(pattern.name)) {
        assert.ok(Math.max(...rgb) > 0, pattern.name + ' loops without a black flash');
      }
    }
    assert.ok(peak > 150, pattern.name + ' has saturated colors');
    assert.ok(frames.size > 10, pattern.name + ' animates');
    assert.equal(controller.finished(), pattern.name === 'All Done', pattern.name + ' completion');
    if (pattern.name === 'All Done') assert.deepEqual(Array.from(controller.step(21000)), [0,0,0,0,0,0]);
    if (['Working','Ember Tide','Purple Tide','Night Rider','Aurora','Ocean'].includes(pattern.name)) {
      assert.ok(asymmetric, pattern.name + ' uses independent LEDs');
    }
  }
  console.log(`${patterns.length} curated patterns passed: parsing, motion, color, seamless ambient loops, and completion.`);
} finally {
  fs.rmSync(temporary, {recursive:true, force:true});
}
