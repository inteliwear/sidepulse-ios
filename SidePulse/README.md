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
- Optional SidePulse Dot folder writes through Files.

The bundle identifier is `io.sidepulse.app`.

## iOS setup

1. Open `SidePulse.xcodeproj` in Xcode.
2. Select the `SidePulse` target.
3. Select your Apple Developer team.
4. Confirm the bundle identifier is `io.sidepulse.app`.
5. Confirm these capabilities:
   - Push Notifications
   - Background Modes -> Remote notifications
6. Build and run on a real iPhone or iPad. APNs push tokens do not work on the
   simulator.
7. Tap **Get Push Token** and copy the token.
8. Tap **Set Up SidePulse Dot Folder**, then select the SidePulse Dot USB drive folder
   containing `LEDS.LED` in Files.

If no SidePulse Dot folder is configured, pushes still appear in the inbox. The app
does not treat that as a user-facing failure.

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
apns-topic: io.sidepulse.app
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
export APNS_BUNDLE_ID="io.sidepulse.app"
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
