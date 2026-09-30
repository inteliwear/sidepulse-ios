"""Prepare bundled browser scripts for offline WKWebView (no module/file fetches)."""
from pathlib import Path
import base64

assets = Path(__file__).resolve().parents[1] / 'SidePulse' / 'PatternPreviewWeb'
(assets / 'engine.js').write_text('window.SDLED_WASM_BASE64 = "' + base64.b64encode((assets / 'sdled.wasm').read_bytes()).decode() + '";\n')
(assets / 'device-preview.js').write_text((assets / 'device-preview.mjs').read_text().replace('export function', 'function').replace('/pattern-assets/', ''))
(assets / 'preview-playback.js').write_text((assets / 'preview-playback.mjs').read_text().replace('export const', 'const').replace('export class', 'class'))
