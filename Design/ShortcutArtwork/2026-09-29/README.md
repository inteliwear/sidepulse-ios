# SidePulse Dot shortcut artwork

Rendered in Blender Cycles from the existing `sidepulse-dot-product.blend` scene on 2026-09-29. The original scene and product mesh geometry are unchanged.

## Deliverables

- `dot-top.png`: true orthographic top view, 1800 × 1800, neutral gray studio surface.
- `dot-angled.png`: angled studio view, 1800 × 1800.
- Matching `-transparent.png` cutouts for compositing.
- Twelve `Shortcut{Pulse,Breathe}Dot{Color}.png` cutouts, 512 × 512, with matching framing. Both LEDs use the named action color. Breathe has a slightly brighter diffuser. These replace the active SVG artwork in the iOS asset catalog under the existing asset names.
- `sidepulse-dot-shortcuts.blend`: editable orange/blue studio scene.

The two-color masters use a warm orange and cool blue emission blend across the frosted diffuser, plus two broad lights directed across the surface away from the connector. This is art-directed illumination, not an optical simulation. The metal uses a rough satin material to avoid sharp reflected stripes. The saturation revision uses Khronos PBR Neutral tone mapping, lower diffuser specular reflection, and restrained emission to preserve richer colors without washing them out to pastels.

## Geometry provenance

Source scene:
`/Users/pero/pgit/sdstatus_bitbang/packaging/renders/dot-2026-09-13/sidepulse-dot-product.blend`

The accompanying original README and builder identify the actual diffuser mesh as `3d/PulseDot_top_glue v77.3mf`, and the connector, PCB and LEDs as tessellated solids from `/Users/pero/Downloads/3D_PCB1_2_2026-06-20.step` at 0.025 mm tolerance. That supplied STEP is present and includes the TYPE-C-SMD_JINGTUOJIN_918-118A2021Y40002 connector. The repository PCB folder and supplied Downloads models were checked. The existing Dot assembly was preserved instead of substituting the other board revisions in `pcb/easyeda`.

## Regenerate

From the iOS repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b \
  --python SidePulse/tools/render_shortcut_artwork.py -- \
  --scene /Users/pero/pgit/sdstatus_bitbang/packaging/renders/dot-2026-09-13/sidepulse-dot-product.blend \
  --output Design/ShortcutArtwork/2026-09-29
```

The studio background is omitted from shortcut icons so the same artwork works on light and dark Shortcuts surfaces. App Intent asset names and action behavior are unchanged. The preview sheets show artwork placement, not a captured Shortcuts screen.

## Validation

The iOS Simulator Debug build succeeded with the new asset catalog. All 68 product meshes and their transforms were compared against the source scene and are unchanged. All twelve icon PNGs have transparency and were visually checked on light and dark backgrounds and at 64 px. Actual display in the Shortcuts app has not been verified.

After rendering, install the assets and regenerate the preview sheets with:

```sh
python3 SidePulse/tools/install_shortcut_artwork.py Design/ShortcutArtwork/2026-09-29
```
