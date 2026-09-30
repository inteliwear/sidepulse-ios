# Offline pattern preview

The app bundles the same device renderer and completion-aware WASM engine as the
SidePulse website at commit 33c6f9b (2026-09-29). CAD renders retain the real Dot
connector and Pro PCB geometry. The SwiftUI controls send structured arguments to
an offline WKWebView; pattern text is never interpolated into JavaScript or HTML.
No network connection is needed and the preview page disallows network requests.

This source snapshot originally came from sdstatus_bitbang, HEAD
bb5910ad713b2fd353f73f8358bc957a662fdd5e, including supplied controller changes.
The browser-only addition is finished(), exposed as sdled_finished, so completion
is independent of the final LED color. These are preview artifacts, not firmware.

Rebuild with `sh SidePulse/tools/preview-wasm/build.sh` from the repository root.
Override WASM_CLANG/WASM_LD if LLVM lives elsewhere. The script also regenerates
the offline base64 bundle and classic JS scripts. After updating the renderer or
playback .mjs sources, run `python3 SidePulse/tools/prepare_pattern_preview.py`.

Verify with `node SidePulse/tools/test-pattern-preview.mjs` and the Swift tests.
Text outside the engine's 512-byte/20-line limits remains editable, savable, and
shareable; the preview reports its error instead of rejecting the document.
