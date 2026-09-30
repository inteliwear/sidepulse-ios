# SidePulse App Store artwork

## Current screenshots

- `01-shortcuts.png` / `.svg` — “Let your agent talk to you with light.”
- `02-computer-status.png` / `.svg` — “Big updates. Tiny light.”
- `03-shortcuts.png` / `.svg` — “Make your Shortcuts glow.” with the dark-mode app display.
- `preview.png` — three-screenshot review image.
- Final screenshots are 1320 × 2868 RGB PNGs with no alpha channel.
- SVGs retain editable headline text and embed the full-resolution product render.
- No visible attribution, branding block, or laptop illustration is included in the current artwork. A magnified close-up highlights the connected Dot at the bottom of each image, with a small SidePulse Dot label. Model provenance is retained below and in `source/iphone-license.txt`.

## App screen

`screens/sidepulse-current-dark.png` is a real iPhone 17 Pro simulator capture from a fresh Debug build of the current working tree (2026-09-29), including the redesigned gradient header, Dot artwork, Shortcuts badge, and Pattern Library. The inbox contains fictional demo updates (“Build complete” and “Your agent needs you”). Demo preferences and a local folder bookmark were configured in the simulator; the app source was not modified for capture. Status bar time is set to 9:41.

## Editable sources

- `source/dot-focus-1.blend` and `source/dot-focus-2.blend` — current main scenes, with packed app screenshots, dedicated screen surfaces, and orange iPhone models.
- `source/render_minimal.py` — prepares and renders the current scenes from the front-facing base scene.
- `source/render_dot_focus.py` — renders the revised main views and enlarged Dot detail from the minimal scenes.
- `source/dot-magnified.blend` — editable close-up scene.
- `source/layout.py` — produces both editable SVG layouts from the renders.
- `source/render_dark_screens.py` — swaps the captured native dark-mode UI into the phone and close-up scenes, keeping the gray studio background.
- `renders/agent-wand.png` — agent mascot, shown at 576 px with a wand trail to the connected Dot.
- `source/iphone-dot.blend` and `source/iphone-dot-detail.blend` — original front-facing base scenes.
- `renders/dot-angled.png` and `renders/dot-top.png` — standalone product renders.

Export the SVGs through Inkscape using `--export-png-color-mode=RGB_8` to avoid alpha channels.

## Design review

Typography uses Avenir Next, with 112 px demi headlines and 52 px medium subtitles across two lines. Display corners now use an inset of the native phone glass outline, with a parallel black bezel; they no longer use a generic rounded rectangle.

The previous drafts had too much supporting copy, nested picture framing, and a blank display. The revised pair uses one concise benefit per image, a short explanatory line, real UI, a consistent neutral studio surface, and safe headline margins. The Dot stays at accurate scale on the phone, while the circular detail gives it a much stronger visual presence. The restrained angles preserve screen readability while showing the orange frame and attached Dot.

References reviewed:
- Apple App Store asset best practices: https://developer.apple.com/app-store/asset-best-practices/
- Apple screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

Apple recommends depicting the app in use, leading with its strongest features, using intentional short text, and keeping focal content legible. These are design principles, not a claim of App Review approval.

## Model attribution

This work is based on **Iphone 17 pro** by **Ibrahim.Bhl**, licensed under **CC BY 4.0**. Modifications: orange finish, material adjustments, physical scaling, display UV mapping, separate Dynamic Island, and composition with SidePulse Dot.

- Model: https://sketchfab.com/3d-models/iphone-17-pro-4aeeeb41f9d14f96bb3f2589edc3edac
- Author: https://sketchfab.com/Ibrahim.Bhl
- License: https://creativecommons.org/licenses/by/4.0/

Selected local source: `/Users/pero/Downloads/iphone-17-pro/source/iphone 17_4.glb`. The other downloaded GLB variants contain the same phone geometry; the original was chosen for its named parts. The bundled license from the downloaded model is retained as `source/iphone-license.txt`. Keep attribution with publicly distributed artwork.
