const RESTART_DELAY_MS = 1500;

// Time only advances while the page is playing. Completion comes from the engine,
// so holds, delays, finite repeats and infinite repeats keep their real timing.
class PreviewPlayback {
  constructor(controller, source) {
    this.controller = controller;
    this.source = source;
  }
  restart() {
    this.controller.reset(0);
    this.elapsed = 0;
    this.waited = 0;
    this.ended = false;
    const result = this.controller.parse(this.source, 0);
    this.rgb = this.controller.step(0);
    return result;
  }
  tick(delta, autoRestart) {
    if (this.ended) {
      if (autoRestart) {
        this.waited += delta;
        if (this.waited >= RESTART_DELAY_MS) this.restart();
      }
    } else {
      this.elapsed += delta;
      this.rgb = this.controller.step(this.elapsed);
      if (this.controller.finished()) { this.ended = true; this.waited = 0; }
    }
    return {rgb:this.rgb, phase:this.ended ? (autoRestart ? 'waiting' : 'finished') : 'playing'};
  }
}
