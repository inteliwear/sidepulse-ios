# SidePulse for iOS

SidePulse is a push inbox that can optionally write LED programs to `LEDS.LED`
on a SidePulse Dot USB drive attached to an iPhone or iPad.

The app supports:

- General-purpose APNs pushes, stored newest-first in the inbox.
- Tiny named-pattern pushes such as `{"pattern":"green_pulse_2"}`.
- Raw LED pushes using `leds`, `LEDS.LED`, or `text`.
- Literal `\n`, `\r`, `\t`, and `\\` escapes in LED text are decoded before
  validation and writing.
- Shortcuts or URL actions such as `sidepulse://write?pattern=success`.
- A Shortcuts action named **Update from Server** that downloads queued LED
  updates from the SidePulse bridge and writes the latest one to the Dot.
- Optional SidePulse Dot folder writes through Files.

The bundle identifier is `io.sidepulse.ios`.

## APNs build environments

The app formats development APNs tokens as `dev_<hex>` and production tokens as
`<hex>`. `SIDEPULSE_APNS_ENVIRONMENT` controls both the app’s
`SidePulseAPNSEnvironment` Info.plist value and its `aps-environment` signing
entitlement. Debug is configured as `development`; Release is configured as
`production`. If a Release build is signed with a development provisioning
profile, explicitly set `SIDEPULSE_APNS_ENVIRONMENT=development` for that
build. A Release archive signed with a development profile while the setting
remains `production` will fail the verification below. TestFlight exports need
production signing and must pass the same check.

For command line exports, use the verified export command. It fails the export
if the finished IPA’s configured environment and signed entitlement disagree:

```sh
tools/export_verified_ipa.sh /path/to/SidePulse.xcarchive /path/to/export /path/to/ExportOptions.plist
```

For exports made in Xcode, check the final artifact against its actual signing
entitlement before installing or uploading it:

```sh
tools/verify_signed_apns_environment.sh /path/to/SidePulse.ipa
```

The check also accepts a signed `.app` bundle and exits with an error if the
configured Info.plist environment is absent, invalid, or differs from the
signed `aps-environment` entitlement.

## License and trademarks

Copyright (c) 2026 InteliWEAR LLC. SidePulse is owned by InteliWEAR LLC.

The project is licensed under the [Mozilla Public License 2.0](../LICENSE).
See the [repository license overview](../README.md#license) for scope and
source-sharing requirements. The SidePulse name and logos are covered by
the separate [trademark policy](../TRADEMARKS.md).

## iOS setup

1. Open `SidePulse.xcodeproj` in Xcode.
2. Select the `SidePulse` target.
3. Select your Apple Developer team.
4. Confirm the bundle identifier is `io.sidepulse.ios`.
5. Confirm these capabilities:
   - Push Notifications
   - Background Modes -> Remote notifications
6. Build and run on a real iPhone or iPad. APNs push tokens do not work on the
   simulator.
7. Run `sidepulse link` on your computer and scan its QR code, or tap **Get Push Token** and copy the token into that command.
8. Tap **Set Up SidePulse Dot Folder**, then select the SidePulse Dot USB drive folder
   containing `LEDS.LED` in Files.

If no SidePulse Dot folder is configured, pushes still appear in the inbox. The app
does not treat that as a user-facing failure.

## Active push keys

Settings → **Active Push Keys** lists locally issued sender keys, displaying
only the last four characters, the last accepted activity time, and lifetime
received count. Counts and keys persist across app launches.
Pairing creates a new random key and sends the suffixed push token to the Mac.
**Copy New Token** creates a key for a manual sender; **Copy Token** on an
existing row reuses that sender's key without displaying the full secret.

**Remove** immediately revokes the key locally. Unknown, missing, and removed
keys are rejected before inbox updates, LED writes, or link-state updates, on
both APNs and queued recovery paths. Receiving a push cannot enroll a key.
Existing senders using an unkeyed token must pair again or use a newly copied
suffixed token. Local Shortcuts and manual writes do not require a remote key.

The bridge strips the suffix before sending to Apple and supplies top-level
`shared_key` and `sidepulse_push_id` fields. Only the top-level key is trusted;
keys inside `data` or `payload` are ignored for authorization. The app uses the
sender's event ID, when present, or the bridge message ID to avoid counting
repeat callbacks/recovery twice (the latest 256 IDs per key are retained).
Messages without an ID count on each receipt; a repeat older than this retained
window can count again.
Full key values are masked in payload summaries and received-message history.
Foreground alerts from inactive keys are suppressed. iOS can still present a
background alert before the app runs; its custom data is not processed.

The included direct push server also accepts the suffixed token and attaches
these fields. It uses its configured APNs environment as before.

## Update action and notification cleanup

**Update from Server** can run without a saved desktop link. Remote updates
still require an active sender key. With no active keys, it clears unauthorized
notifications and returns without fetching updates. Missing setup, ignored
updates, and network failures are recorded in diagnostics instead of producing
Shortcuts error alerts.

Notifications with missing, unknown, or removed keys are dismissed when the app
handles them, becomes active, removes a key, or runs the update action. Rejection
never writes LEDs, changes link state, records sender activity, or adds
an inbox entry. Valid notifications keep their normal presentation; matching
LED-update notifications are cleared after a successful write. Matching uses
sender identity and event/message IDs, with content matching for legacy pushes.
Successful-write receipts are scoped to the local sender record and message ID.
Recovery can retry failed writes or updates received before a folder was selected,
without counting the same delivery twice. An older successful write of identical
LED text does not dismiss a newer failed update's notification.

Deploy the bridge with suffixed-token support and update the desktop CLI before
using normal sender pushes with this build. The CLI must preserve the complete
token and key suffix; the bridge must supply the authoritative top-level key
on both APNs and queued recovery messages. The app rejects older unkeyed
messages even though the bridge continues to accept them for legacy clients.

## Background pushes

SidePulse handles silent pushes in
`application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`. Silent
delivery is still controlled by iOS: Background App Refresh must be enabled, the
app must not be force-quit, and delivery can be delayed. Visible alert pushes
are also processed when delivered or opened.

For silent/background writes, APNs should use:

```text
apns-push-type: background
apns-priority: 5
apns-topic: io.sidepulse.ios
```

## Payloads

Full LED text wins over pattern names:

```json
{
  "aps": {"content-available": 1},
  "LEDS.LED": "#00ff00 280ms pulse\noff 160ms none\n"
}
```

Tiny named-pattern push:

```json
{
  "aps": {"content-available": 1},
  "pattern": "green_pulse_2"
}
```

Supported pattern names:

```text
off
green_pulse_2
success
error
working
waiting
white_breathe
```

The app also accepts arbitrary `data` or custom payload fields and stores them
as general pushes when no LED text or known pattern is present.

## Fast push server

Create a virtual environment:

```sh
cd ios/SidePulse/tools
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

Set APNs credentials and server defaults:

```sh
export APNS_TEAM_ID="YOUR_TEAM_ID"
export APNS_KEY_ID="YOUR_KEY_ID"
export APNS_AUTH_KEY="/path/to/AuthKey_YOUR_KEY_ID.p8"
export APNS_BUNDLE_ID="io.sidepulse.ios"
export APNS_ENV="sandbox"
export SIDEPULSE_DEVICE_TOKEN="token copied from the app"
export SIDEPULSE_SHARED_SECRET="choose-a-local-testing-secret"
```

Run the server:

```sh
python server.py
```

Open `http://127.0.0.1:8787` for the simple sender page, or use curl:

```sh
curl -X POST http://127.0.0.1:8787/v1/push \
  -H "Authorization: Bearer $SIDEPULSE_SHARED_SECRET" \
  -H "content-type: application/json" \
  -d '{"pattern":"green_pulse_2"}'
```

Send raw LED text:

```sh
curl -X POST http://127.0.0.1:8787/v1/push \
  -H "Authorization: Bearer $SIDEPULSE_SHARED_SECRET" \
  -H "content-type: application/json" \
  -d '{"leds":"#00ff00 280ms pulse\noff 160ms none\n"}'
```

The helper script calls the same endpoint:

```sh
python send_push.py --pattern green_pulse_2
```

## API

`GET /health`

Returns server health.

`GET /v1/patterns`

Returns server-known pattern names and LED text.

`POST /v1/push`

Friendly envelope:

```json
{
  "device_token": "optional if SIDEPULSE_DEVICE_TOKEN is set",
  "pattern": "green_pulse_2",
  "leds": "optional raw LEDS.LED",
  "payload": {"optional": "extra custom payload fields"},
  "apns": {
    "push_type": "background",
    "priority": 5,
    "collapse_id": "optional",
    "expiration": "optional"
  }
}
```

`POST /v1/push/raw`

Passes the JSON body through as the exact APNs payload. Provide the device token
with `?device_token=...`, `X-Side-Device-Token`, or `SIDEPULSE_DEVICE_TOKEN`.
Optional APNs overrides can be sent as `apns-push-type`, `apns-priority`,
`apns-collapse-id`, `apns-expiration`, or `apns-topic` request headers.

```sh
curl -X POST "http://127.0.0.1:8787/v1/push/raw?device_token=$SIDEPULSE_DEVICE_TOKEN" \
  -H "Authorization: Bearer $SIDEPULSE_SHARED_SECRET" \
  -H "content-type: application/json" \
  -H "apns-push-type: background" \
  -H "apns-priority: 5" \
  -d '{"aps":{"content-available":1},"pattern":"success","data":{"source":"curl"}}'
```

## Notes

- The server uses FastAPI, uvicorn, a shared `httpx.AsyncClient(http2=True)`,
  connection pooling, and cached APNs JWT refresh.
- SidePulse server settings use the `SIDEPULSE_*` environment-variable prefix.
- Keep LED programs at or below 512 bytes and 20 physical lines for the SidePulse Dot writer. The DSL is
  documented in the repo root at `LEDS_FORMAT.md`.
- The generated source app icon is kept at `SidePulseIconSource.png`.

## Pattern Library

The home screen has a compact row with the rendered Dot, an animated rainbow
“Pulse” wordmark (static when Reduce Motion is enabled), and Settings. The
larger native Shortcuts badge opens SidePulse’s actions.

Pattern Library includes starter Blink/Breathe patterns and an orange/blue
sequence. Tap a pattern to preview or play it, or choose **New**.
The editor supports independent colors for both LEDs, Hold/Fade/Pulse effects,
50 ms–10 s steps, reordering, and up to 20 plays or continuous looping. Patterns
are limited to 12 steps and validated against the Dot’s 512-byte program limit.
The on-screen preview runs the device language; screen colors are not a
calibrated representation of LED output. Creating and previewing patterns works
without a connected Dot. Playing asks for the USB folder when it is not configured.

**Browse library** opens the searchable library. Use Edit, Duplicate, or swipe to delete.
Saved patterns live in the app’s Application Support directory and survive app
updates. Deleting the app removes this local library, so share/export copies of
patterns you want to keep.

**Share preview link** creates a self-contained `https://sidepulse.io/pattern#…` link.
Recipients can preview it using the device’s WASM engine on the website, download
the original `.led` file, or choose **Open in SidePulse** to review and save a copy.
Universal Links also route this page into updated installations of the app.
Large imports that exceed the link payload limit use file sharing instead.

**Share .led file** exports the actual plain-text `.led` device program through the
system share sheet. Recipients with SidePulse can open the document, preview or
edit it, and choose **Save copy**. The library’s + menu also supports importing
from Files. The filename supplies the pattern name. Import validates size, timing, and colors and
assigns a fresh ID; it never overwrites an existing pattern or plays it automatically.
All UTF-8 `.led` programs up to 64 KB can be imported and shared unchanged.
**Edit .led text** opens a freeform monospaced editor for any pattern. It preserves
comments, whitespace, and unsupported commands exactly. Apply refreshes the
preview; Save saves the current text even if it has not been applied. Reset original
restores the opening draft, and Cancel protects unsaved changes. Editing a saved
pattern keeps its ID, so existing Shortcuts continue to use it.

The pattern detail and text editor use the website’s actual Dot/Pro CAD renders,
soft diffused light and glow, and adaptive light/dark cards. Their bundled offline
WASM engine supports the full device language, including brightness, indexed
colors, and repeats. Preview starts automatically. Restart resets it, and an
optional default-on 1.5-second restart runs only after a finite program completes.
App backgrounding pauses playback. A preview syntax/size error never prevents
saving or sharing an otherwise valid UTF-8 document up to 64 KB.

Programs outside the visual editor’s supported subset open in the text editor.
Visual step editing remains available for supported patterns. Hardware playback retains the device’s size and line limits.
For supported imports, changing steps regenerates the program; renaming alone
preserves the original formatting and comments. Earlier `.sidepulsepattern` documents remain readable.
An example document is in `../Design/PatternLibrary/Examples/`.

The SidePulse page in Shortcuts shows a **Pattern Library** collection alongside
Blink and Breathe, populated from the saved library and refreshed after saves,
imports, renames, and deletions. In a shortcut or automation, add **Play SidePulse
Pattern**, then tap its **Pattern** field for a searchable picker of saved patterns. Selections use stable IDs, so renaming or editing a pattern updates
future runs without reconfiguring the shortcut. Deleted selections produce a
message asking the user to choose another pattern.

Validation: `swift test --package-path SidePulse` includes library persistence,
share round trips, malformed imports, device limits, and preview timing tests.

Offline preview validation: `node SidePulse/tools/test-pattern-preview.mjs` from the repository root. Engine source and regeneration instructions are in `tools/preview-wasm/README.md`.

### Pattern thumbnails

The app renders transparent PNG thumbnails for both Pattern Library and Shortcuts
from the actual Dot CAD render. A native build of the same LED controller used by
the web preview samples a representative bright frame (8 ms samples over at most
the first two minutes, stopping at completion). This supports raw text commands,
independent LED colors, pulse peaks, delays, and output brightness. Thumbnails are
static; opening a pattern gives the full animated preview. Invalid/oversized
programs use a neutral device with a document symbol instead of invented colors.

The PNG cache is keyed by the exact source, so edited programs receive new images;
saving also refreshes Shortcuts. Nothing is uploaded to generate these images.
The native sampler is covered by `tools/test-pattern-thumbnails.cpp`:

```sh
xcrun clang++ -std=c++17 -O2 -x c++ SidePulse/PatternThumbnailSampler.mm tools/test-pattern-thumbnails.cpp -o /tmp/sidepulse-thumbnail-tests
/tmp/sidepulse-thumbnail-tests
```
