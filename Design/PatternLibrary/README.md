# Pattern Library redesign

Implemented in the native app, including the device/wordmark/settings header,
12-second rainbow color cycle with Reduce Motion support, larger Shortcuts badge,
persistent visual pattern editor, playback preview, share/import documents, and
saved-pattern App Intents picker.

`Examples/Sunset.led` is a working share/import example.
The screenshots are from an iPhone 17 Pro Max simulator. The sample Sunset
pattern was imported during verification; the physical phone gets the normal
starter library unless it already has saved patterns.

Verified before the .led format update: 17 unit tests pass, simulator and device builds succeed, edits persist,
and opening a shared document from a cold launch presents a review screen and
saves a copy with a new identity. Share sheet opens with a pattern document.
Actual delivery to another person's phone and LED output on connected hardware
have not been tested in this session.

The balance revision centers the wordmark between the device and Settings, groups
Shortcuts and Off into one utility row, removes the tagline and large creation
bar, and uses rendered devices in denser library rows. `balanced-home.png` and
`balanced-home-dark.png` show this revision.

`refined-header.png` shows the subsequent header refinement: more vertical space,
a larger wordmark, and a smoothly scrolling, curated rainbow spectrum.

`shortcuts-badge.png` restores the standalone outlined Shortcuts badge at 130%
scale and places an explicitly labeled “Turn off LEDs” control below the library.

Sharing now exports the plain-text `.led` program used by the device. Imports
recover the name from the filename and preserve the original program.
The old `.sidepulsepattern` example remains as a legacy import fixture.

Verified for the .led update: 21 tests pass; simulator and signed device builds
succeed. Save to Files creates `Sunset.led` with the expected plain-text commands;
opening that exported file from a cold launch presents the import preview with
the filename and both steps preserved. The shared firmware parser accepts the
example program. Installed and launched on the connected iPhone.

The home badge now reads “SidePulse in Shortcuts”, with “Shortcuts setup recipes”
directly beneath it linking to https://sidepulse.io/setup/dot/recipes. The badge
keeps the native ShortcutsLink action; simulator verification opens SidePulse’s
actions in Shortcuts. The supplied recipes URL returned HTTP 404 during checking.
`ShortcutsBadgeIcon` is the unmodified Shortcuts app icon from Apple's bundled
iOS 18.2 simulator runtime, used to identify the destination app.

The Pulse gradient now uses the website’s accent palette and double-width spectrum,
scrolling continuously over twelve seconds (half the website’s speed). Reduce Motion
keeps a static gradient.

Import compatibility update: arbitrary UTF-8 .led programs up to 64 KB now save
with their original source preserved. Unsupported commands get a read-only source
view instead of an import failure or inaccurate preview. Rename, duplicate, share,
and device playback remain available; device writes retain their existing limits.
Visual edits of supported imports regenerate the program, with a formatting/comment
notice; a rename preserves the original file. Existing libraries without the optional
source field remain readable.

Verified with the exact 38-byte `/Volumes/PulseDot/INIT.LED` (brightness 40 and a
single-color pulse), copied to `Examples/INIT.LED`: cold-open import and Save copy
work in the simulator and persist identical bytes. All 24 tests pass and both
simulator and signed device builds succeed. No files on PulseDot were changed.

Web sharing: primary sharing now sends a self-contained HTTPS pattern link, with
.led file sharing retained. Version-1 base64url JSON in the fragment contains the
name and exact LED source, capped at 8192 encoded characters. Both custom-scheme
and Universal Link handlers present import review without auto-saving or playing.

Website changes are in ../sidepulse.io (from the repository root’s parent):
`public/pattern.md`, `pattern-template.html`, `pattern-assets/`, and Firebase
hosting association configuration. The preview uses the existing sdstatus_bitbang
WASM engine for both Dot and Pro. The dedicated page omits analytics so encoded
pattern contents are not sent in analytics page URLs. Patterns aren’t stored on a
server; links are still readable by anyone they are shared with.

Verified: 26 Swift tests, Node codec/WASM playback tests including brightness 40,
simulator and signed device builds, custom-scheme import review with exact source,
mobile and desktop browser layouts, and a browser download identical to INIT.LED.
Published to sidepulse.io. Both the origin and Apple’s association CDN return the
correct app association. Automatic Universal Link routing on the physical phone
remains unverified; the update is installed but the phone was locked at launch.
`web-pattern-preview.png` captures the live page. Recipients need an app build
containing these new handlers; the public TestFlight build has not been updated.

## iOS web-style preview and free text editor (2026-09-29)

Pattern detail now matches the shared web page: adaptive studio cards, diffused
CAD product rendering, glow, larger titles, and blue actions. Dot/Pro previews run
the bundled offline WASM engine, with Restart and optional delayed auto-restart.
The new Edit .led text sheet supports any UTF-8 program up to 64 KB; Apply updates
the preview and Save preserves the exact text and original library identity.
Visual editing remains available as Edit steps. Unsupported imports go straight
to the text editor instead of a read-only source panel.

Verified 29 Swift tests and the offline native-bridge engine tests. Simulator
checks covered the original INIT.LED brightness program, text Apply/Save with
exact persisted comments, Dot/Pro switching, nested visual-to-text editing, and
light/dark appearance. Both simulator and signed device builds passed; the
signed APNs environment was verified as development. Installed on Peter's
16 Pro Max; automatic launch was blocked by the phone being locked.

Screenshots: `ios-web-style-dark.png`, `ios-free-text-editor-dark.png`.

## Final review (2026-09-30)

Saved patterns now appear in Shortcuts' Pattern Library collection. The app and
Shortcuts use cached thumbnails sampled from each exact program by the native
controller, including brightness and independent LED colors. See
`shortcuts-rendered-pattern-colors.png` for the verified system UI.

Review fixed imported step edits previewing stale source, and notification cleanup
confusing a prior successful write with a newer failed update. Failed USB writes
and deliveries received before folder setup remain eligible for queued retry.

Validation: 40 Swift tests, 11 push-server tests, offline WASM preview tests,
native thumbnail sampling tests, simulator build, signed device build, and signed
development APNs entitlement verification passed. Generated preview scripts match
their sources; image catalog references and App Store PNG dimensions were checked.
The review build was not deployed or uploaded to TestFlight. End-to-end delivery
through the production bridge and USB hardware was not re-tested in this review.
