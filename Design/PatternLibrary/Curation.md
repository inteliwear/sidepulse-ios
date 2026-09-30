# Curated Pattern Library — 2026-09-30

Twelve defaults replace the repeated blink/breathe color grid. The first four
cover useful status signals and a two-color ambient preview. Every entry has a
short description of its movement instead of a generic imported-file label.

| Pattern | Motion |
| --- | --- |
| Working | Staggered cyan pulses, the CLI working signal |
| Needs You | Warm amber attention pulse |
| All Done | Two green pulses, then off |
| Aurora | Violet, mint, and blue crossing fades |
| Ember Tide | CLI ember working wave |
| Purple Tide | CLI magenta working wave |
| Night Rider | CLI red scanner with a short trailing pulse |
| Heartbeat | Rose double beat and pause |
| Sunset | Tangerine, rose, and violet fades |
| Ocean | Blue and turquoise trade places |
| Candlelight | Uneven amber flicker with independent LEDs |
| Spectrum | Saturated rainbow with offset colors |

Ambient programs fade continuously across repeats, without resetting to black.
All Done finishes; the other eleven loop. All programs fit the Dot's 512-byte,
20-line limits. Advanced programs retain the exact .led source and use the text
editor; All Done and Heartbeat also support the visual step editor.

## References

Reviewed the current `inteliwear/sidepulse` Cyan, Ember, and Purple agent profiles,
`src/sidepulse/led_status.py`, and the actual two-LED animation resources. The five
copied programs matched GitHub main by Git blob hash on 2026-09-30:

- [Working](https://github.com/inteliwear/sidepulse/blob/main/src/sidepulse/resources/animations/cyan-roll-2.LED)
- [Needs You](https://github.com/inteliwear/sidepulse/blob/main/src/sidepulse/resources/animations/amber-pulse.LED)
- [Ember Tide](https://github.com/inteliwear/sidepulse/blob/main/src/sidepulse/resources/animations/ember-tide-2.LED)
- [Purple Tide](https://github.com/inteliwear/sidepulse/blob/main/src/sidepulse/resources/animations/purple-tide-2.LED)
- [Night Rider](https://github.com/inteliwear/sidepulse/blob/main/src/sidepulse/resources/animations/night-rider-2.LED)

All Done uses the repo's green completion palette with a new finite double pulse.
The other ambient and heartbeat programs are authored for this collection.

## Existing libraries

Old array libraries gain the new collection at the front without altering existing
IDs, source, names, or custom edits. Untouched old presets appear under a collapsed
Classic colors group and remain searchable. Existing Shortcuts still resolve their
original IDs; the suggested Pattern Library collection emphasizes the new entries.

Saving writes a versioned library document. Later loads do not re-add deleted
presets. An intentionally empty library, including a legacy empty array, stays
empty. Reading alone does not overwrite an existing file.

## Verification

Run `swift test --package-path SidePulse` for persistence, migration, editing and
sharing coverage. Run `node SidePulse/tools/test-curated-patterns.mjs` to compile
and export the actual Swift catalog and exercise all twelve programs through the
bundled firmware WASM: parse limits, animated frames, saturated colors, staggered
LEDs, continuous ambient loops, and finite completion to black.

## Upstream program license

MIT License

Copyright (c) 2026 Peter Kuhar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
