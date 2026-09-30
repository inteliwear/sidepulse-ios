// Offline native bridge. Source enters as a structured argument, never executable code.
let playback, paint, settings, previousFrame, requestVersion = 0, lastStatus = '';
function report(message) {
  if (message === lastStatus) return;
  lastStatus = message;
  window.webkit?.messageHandlers.preview.postMessage(message);
}
window.configurePreview = async function(next) {
  const reload = !settings || next.source !== settings.source || next.count !== settings.count || next.restart !== settings.restart;
  settings = next;
  if (!reload) return;
  const version = ++requestVersion;
  playback = null;
  report('Loading preview…');
  try {
    const controller = await createSdLedController({ledCount:next.count});
    if(version !== requestVersion) return;
    paint = createDevicePreview(document.getElementById('lights'),next.count);
    const candidate = new PreviewPlayback(controller,next.source);
    const result = candidate.restart();
    paint(candidate.rgb);
    if(!result.ok) {
      report(`Preview unavailable: ${result.errorName.replaceAll('-',' ')}${result.line ? ` at line ${result.line}, column ${result.column}` : ''}. You can still edit and save this file.`);
      return;
    }
    playback = candidate;
    previousFrame = null;
    report('Playing preview · Colors may look different on your device.');
  } catch(error) {
    report('Preview couldn’t load. Your pattern is still available to edit and save.');
  }
};
function frame(now) {
  if(playback && settings.active && !document.hidden) {
    const delta = previousFrame == null ? 0 : Math.min(100,Math.max(0,now-previousFrame));
    const state = playback.tick(delta,settings.autoRestart);
    paint(state.rgb);
    report(state.phase==='waiting' ? 'Restarting in 1.5 seconds…' : state.phase==='finished' ? 'Pattern finished. Tap Restart to play again.' : 'Playing preview · Colors may look different on your device.');
    previousFrame = now;
  } else { previousFrame = null; }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
