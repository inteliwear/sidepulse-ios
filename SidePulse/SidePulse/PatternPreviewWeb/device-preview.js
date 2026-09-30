// Live lighting over the existing CAD product renders. No connector geometry is redrawn.
const devices = {
  2: {
    name: 'SidePulse Dot', image: 'dot-preview.png', width: 1800, height: 1800,
    viewBox: '220 210 1360 1270',
    diffuser: 'M338 908 H1461 L1473 919 V1135 Q1473 1201 1371 1256 H429 Q326 1200 326 1135 V920 Z',
    left: 326, right: 1473, top: 908, bottom: 1256,
  },
  8: {
    name: 'SidePulse Pro', image: 'pro-preview.png', width: 3600, height: 2400,
    viewBox: '160 140 3280 2210',
    diffuser: 'M306 1755 H3294 L3306 1767 V2095 L3280 2140 H318 L294 2095 V1767 Z',
    left: 294, right: 3306, top: 1755, bottom: 2140,
  },
};
const ns = 'http://www.w3.org/2000/svg';
const el = (name, attrs = {}) => {
  const node = document.createElementNS(ns, name);
  for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
  return node;
};
function createDevicePreview(container, count) {
  const d = devices[count];
  container.classList.toggle('pro', count === 8);
  const svg = el('svg', {viewBox:d.viewBox, 'aria-hidden':'true'});
  const defs = el('defs');
  const clip = el('clipPath', {id:'diffuser-clip'});
  clip.append(el('path', {d:d.diffuser}));
  const gray = el('filter', {id:'frost-neutral', 'color-interpolation-filters':'sRGB'});
  gray.append(el('feColorMatrix', {type:'saturate', values:0}));
  const gradient = el('linearGradient', {id:'led-colors', gradientUnits:'userSpaceOnUse', x1:d.left, x2:d.right, y1:0, y2:0});
  const spill = el('linearGradient', {id:'spill-colors'});
  const stops = [], spillStops = [];
  for (let i=0; i<=64; i++) {
    const offset = `${i/64*100}%`;
    const stop = el('stop', {offset}), spillStop = el('stop', {offset});
    gradient.append(stop); spill.append(spillStop);
    stops.push(stop); spillStops.push(spillStop);
  }
  const blur = el('filter', {id:'surface-blur', x:'-40%', y:'-150%', width:'180%', height:'400%'});
  blur.append(el('feGaussianBlur', {stdDeviation:count===2 ? 55 : 95}));
  const halo = el('filter', {id:'diffuser-halo', x:'-50%', y:'-180%', width:'200%', height:'460%'});
  halo.append(el('feGaussianBlur', {stdDeviation:count===2 ? 90 : 170}));
  const bloom = el('filter', {id:'diffuser-bloom', x:'-30%', y:'-100%', width:'160%', height:'300%'});
  bloom.append(el('feGaussianBlur', {stdDeviation:count===2 ? 26 : 48}));
  const finish = el('linearGradient', {id:'frost-finish', x1:0, x2:0, y1:0, y2:1});
  for(const [offset,color,opacity] of [['0%','#fff',.25],['28%','#fff',.04],['65%','#fff',0],['100%','#101321',.20]]) {
    finish.append(el('stop', {offset,'stop-color':color,'stop-opacity':opacity}));
  }
  defs.append(clip,gray,gradient,spill,blur,halo,bloom,finish); svg.append(defs);
  // Light falls outward, beyond the diffuser, with an unlit contact shadow beneath it.
  svg.append(el('ellipse', {cx:(d.left+d.right)/2,cy:d.bottom+35,rx:(d.right-d.left)*.45,ry:45,fill:'#111827',opacity:.22,filter:'url(#surface-blur)'}));
  svg.append(el('path', {d:d.diffuser,fill:'url(#spill-colors)',filter:'url(#diffuser-halo)',opacity:.8}));
  const imageAttrs = {href:`${d.image}`,width:d.width,height:d.height};
  svg.append(el('image', imageAttrs));
  // Keep the live surface spill above the render's baked shadow so dim colors
  // remain visible, especially against a dark studio background.
  svg.append(el('ellipse', {cx:(d.left+d.right)/2,cy:d.bottom+65,rx:(d.right-d.left)*.52,ry:count===2 ? 85 : 115,fill:'url(#spill-colors)',filter:'url(#surface-blur)',opacity:.8,style:'mix-blend-mode:screen'}));
  const surface = el('g', {'clip-path':'url(#diffuser-clip)',style:'isolation:isolate'});
  surface.append(el('image', {...imageAttrs,filter:'url(#frost-neutral)'}));
  surface.append(el('path', {d:d.diffuser, fill:'url(#led-colors)',style:'mix-blend-mode:color'}));
  surface.append(el('path', {d:d.diffuser, fill:'url(#led-colors)',opacity:.48}));
  surface.append(el('path', {d:d.diffuser, fill:'url(#frost-finish)'}));
  svg.append(surface);
  svg.append(el('path', {d:d.diffuser,fill:'none',stroke:'url(#spill-colors)','stroke-width':count===2 ? 24 : 42,filter:'url(#diffuser-bloom)',opacity:.75,style:'mix-blend-mode:screen'}));
  container.replaceChildren(svg);
  container.parentElement.setAttribute('aria-label', `${d.name} with a live diffused LED pattern`);
  return rgb => {
    stops.forEach((stop,i) => {
      // Overlapping light fields soften the boundaries between LEDs inside the diffuser.
      const weights = Array.from({length:count}, (_, led) =>
        Math.exp(-.5 * Math.pow((i/64*count - led - .5)/.62, 2)));
      const total = weights.reduce((a,b)=>a+b,0);
      const channels = [0,1,2].map(channel => Math.round(weights.reduce(
        (sum,weight,led)=>sum+weight*rgb[led*3+channel],0)/total));
      const peak = Math.max(...channels);
      // Keep unlit frosted material visible, while retaining distinct brightness levels.
      const ambient = 168 * Math.pow(1-peak/255, 2);
      stop.setAttribute('stop-color', `rgb(${channels.map(c=>Math.round(Math.min(255,ambient+c*1.1))).join(',')})`);
      spillStops[i].setAttribute('stop-color',`rgb(${channels.map(c=>peak ? Math.round(c/peak*255) : 0).join(',')})`);
      spillStops[i].setAttribute('stop-opacity', (Math.pow(peak/255,.75)*.85).toFixed(3));
    });
  };
}
