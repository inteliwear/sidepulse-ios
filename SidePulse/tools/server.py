#!/usr/bin/env python3
from __future__ import annotations

import copy
import html
import json
import os
from typing import Any
from urllib.parse import parse_qs

import uvicorn
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import HTMLResponse

from apns_client import (
    APNsClient,
    APNsConfig,
    APNsConfigError,
    APNsResponse,
    LEDPayloadError,
    normalize_leds_text,
    validate_leds_text,
)
from patterns import PATTERNS, pattern_names


DEFAULT_PORT = 8787
APNS_HEADER_ALIASES = {
    "push_type": "apns-push-type",
    "priority": "apns-priority",
    "collapse_id": "apns-collapse-id",
    "expiration": "apns-expiration",
    "topic": "apns-topic",
}
RESERVED_ENVELOPE_KEYS = {
    "device_token",
    "pattern",
    "leds",
    "LEDS.LED",
    "LEDS.led",
    "text",
    "payload",
    "apns",
    "alert",
}


app = FastAPI(title="SidePulse Push Server", version="1.0")


async def require_bearer_auth(authorization: str | None = Header(default=None)) -> None:
    shared_secret = shared_secret_from_env()
    if not shared_secret:
        return

    if authorization == f"Bearer {shared_secret}":
        return

    raise HTTPException(status_code=401, detail="Unauthorized")


@app.on_event("shutdown")
async def shutdown() -> None:
    client = getattr(app.state, "apns_client", None)
    if client is not None and hasattr(client, "aclose"):
        await client.aclose()


@app.get("/health")
async def health() -> dict[str, Any]:
    return {"ok": True, "service": "sidepulse-push"}


@app.get("/v1/patterns")
async def patterns() -> dict[str, Any]:
    return {
        "patterns": [PATTERNS[name].as_public_dict() for name in pattern_names()],
    }


@app.get("/", response_class=HTMLResponse)
async def index() -> str:
    return index_html()


@app.post("/v1/push")
async def push(
    request: Request,
    _: None = Depends(require_bearer_auth),
) -> dict[str, Any]:
    envelope = await read_json_object(request)
    device_token = resolve_device_token(envelope.get("device_token"))
    if not device_token:
        raise HTTPException(status_code=400, detail="Missing device token")

    payload = build_friendly_payload(envelope)
    headers = apns_headers_from_options(envelope.get("apns"), payload)
    response = await send_apns(device_token, payload, headers)

    pattern = envelope.get("pattern")
    return response_payload(
        response,
        extra={
            "pattern": pattern if isinstance(pattern, str) else None,
            "known_pattern": isinstance(pattern, str) and pattern in PATTERNS,
        },
    )


@app.post("/v1/push/raw")
async def push_raw(
    request: Request,
    device_token: str | None = Query(default=None),
    _: None = Depends(require_bearer_auth),
) -> dict[str, Any]:
    payload = await read_json_object(request)
    token = resolve_device_token(device_token or request.headers.get("x-side-device-token"))
    if not token:
        raise HTTPException(status_code=400, detail="Missing device token")

    headers = apns_headers_from_request(request, payload)
    response = await send_apns(token, payload, headers)
    return response_payload(response)


@app.post("/push")
async def legacy_push(
    request: Request,
    device_token: str | None = Query(default=None),
    key: str | None = Query(default=None),
) -> dict[str, Any]:
    require_legacy_auth(key, request.headers.get("authorization"))
    envelope = await read_legacy_body(request)
    if device_token:
        envelope["device_token"] = device_token
    if "key" in envelope:
        envelope.pop("key", None)

    token = resolve_device_token(envelope.get("device_token"))
    if not token:
        raise HTTPException(status_code=400, detail="Missing device token")

    payload = build_friendly_payload(envelope)
    headers = apns_headers_from_options(envelope.get("apns"), payload)
    response = await send_apns(token, payload, headers)
    return response_payload(response, extra={"legacy": True})


def require_legacy_auth(key: str | None, authorization: str | None) -> None:
    shared_secret = shared_secret_from_env()
    if not shared_secret:
        return

    if authorization == f"Bearer {shared_secret}" or key == shared_secret:
        return

    raise HTTPException(status_code=401, detail="Unauthorized")


def shared_secret_from_env() -> str:
    return os.environ.get("SIDEPULSE_SHARED_SECRET", "")


def resolve_device_token(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return os.environ.get("SIDEPULSE_DEVICE_TOKEN")


async def read_json_object(request: Request) -> dict[str, Any]:
    try:
        loaded = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {exc}") from exc

    if not isinstance(loaded, dict):
        raise HTTPException(status_code=400, detail="JSON body must be an object")
    return loaded


async def read_legacy_body(request: Request) -> dict[str, Any]:
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        return await read_json_object(request)

    body = await request.body()
    if not body:
        return {}

    if "application/x-www-form-urlencoded" in content_type:
        parsed = parse_qs(body.decode("utf-8"), keep_blank_values=True)
        return {key: values[-1] for key, values in parsed.items()}

    return {"leds": body.decode("utf-8")}


def build_friendly_payload(envelope: dict[str, Any]) -> dict[str, Any]:
    payload = envelope.get("payload")
    if payload is None:
        payload = {}
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="payload must be an object")

    apns_payload = copy.deepcopy(payload)
    for key, value in envelope.items():
        if key not in RESERVED_ENVELOPE_KEYS:
            apns_payload.setdefault(key, value)

    aps = apns_payload.get("aps")
    if aps is None:
        aps = {}
    if not isinstance(aps, dict):
        raise HTTPException(status_code=400, detail="payload.aps must be an object")

    alert = envelope.get("alert")
    if isinstance(alert, str) and alert:
        aps["alert"] = {"title": "SidePulse", "body": alert}
        aps["sound"] = "default"
    else:
        aps.setdefault("content-available", 1)

    apns_payload["aps"] = aps

    led_text = first_led_text(envelope)
    if led_text is not None:
        led_text = normalize_leds_text(led_text)
        try:
            validate_leds_text(led_text)
        except LEDPayloadError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        apns_payload["leds"] = led_text

    pattern = envelope.get("pattern")
    if isinstance(pattern, str) and pattern:
        apns_payload["pattern"] = pattern

    data = envelope.get("data")
    if isinstance(data, dict):
        apns_payload.setdefault("data", data)

    return apns_payload


def first_led_text(envelope: dict[str, Any]) -> str | None:
    for key in ("leds", "LEDS.LED", "LEDS.led", "text"):
        value = envelope.get(key)
        if isinstance(value, str):
            return value
    return None


def apns_headers_from_options(options: Any, payload: dict[str, Any]) -> dict[str, str]:
    if options is None:
        options = {}
    if not isinstance(options, dict):
        raise HTTPException(status_code=400, detail="apns must be an object")

    headers: dict[str, str] = {}
    for key, value in options.items():
        if value is None:
            continue
        header_name = APNS_HEADER_ALIASES.get(key, key)
        if header_name.startswith("apns-"):
            headers[header_name] = str(value)

    headers.setdefault("apns-push-type", default_push_type(payload))
    headers.setdefault("apns-priority", "10" if headers["apns-push-type"] == "alert" else "5")
    return headers


def apns_headers_from_request(request: Request, payload: dict[str, Any]) -> dict[str, str]:
    headers: dict[str, str] = {}
    for header_name in ("apns-push-type", "apns-priority", "apns-collapse-id", "apns-expiration", "apns-topic"):
        value = request.headers.get(header_name) or request.headers.get("x-" + header_name)
        if value:
            headers[header_name] = value

    for option_name, header_name in APNS_HEADER_ALIASES.items():
        value = request.query_params.get(option_name) or request.query_params.get(header_name)
        if value:
            headers[header_name] = value

    headers.setdefault("apns-push-type", default_push_type(payload))
    headers.setdefault("apns-priority", "10" if headers["apns-push-type"] == "alert" else "5")
    return headers


def default_push_type(payload: dict[str, Any]) -> str:
    aps = payload.get("aps")
    if isinstance(aps, dict) and "alert" in aps:
        return "alert"
    return "background"


async def send_apns(device_token: str, payload: dict[str, Any], headers: dict[str, str]) -> APNsResponse:
    client = await get_apns_client()
    try:
        return await client.send(device_token, payload, headers=headers)
    except (APNsConfigError, OSError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


async def get_apns_client() -> APNsClient:
    client = getattr(app.state, "apns_client", None)
    if client is not None:
        return client

    client = APNsClient(APNsConfig.from_env())
    app.state.apns_client = client
    return client


def response_payload(response: APNsResponse, *, extra: dict[str, Any] | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "ok": response.ok,
        "status_code": response.status_code,
        "apns_id": response.apns_id,
        "response": response.body,
    }
    if extra:
        payload.update(extra)

    if not response.ok:
        raise HTTPException(status_code=502, detail=payload)

    return payload


def index_html() -> str:
    default_token = html.escape(os.environ.get("SIDEPULSE_DEVICE_TOKEN", ""))
    default_secret = html.escape(shared_secret_from_env())
    options = "\n".join(
        f'<option value="{html.escape(name)}">{html.escape(name)}</option>' for name in pattern_names()
    )
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SidePulse Push Server</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 2rem; max-width: 760px; color: #111827; }}
    label {{ display: block; font-weight: 650; margin-top: 1rem; }}
    input, select, textarea {{ box-sizing: border-box; border: 1px solid #cbd5e1; border-radius: 6px; font: inherit; padding: 0.55rem; width: 100%; }}
    textarea {{ min-height: 150px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }}
    button {{ background: #111827; border: 0; border-radius: 6px; color: white; font: inherit; font-weight: 700; margin-top: 1rem; padding: 0.65rem 0.9rem; }}
    pre {{ background: #f1f5f9; border-radius: 6px; overflow: auto; padding: 0.8rem; }}
  </style>
</head>
<body>
  <h1>SidePulse Push Server</h1>
  <label>Device token</label>
  <input id="deviceToken" value="{default_token}" autocomplete="off">
  <label>Bearer secret</label>
  <input id="secret" value="{default_secret}" autocomplete="off">
  <label>Pattern</label>
  <select id="pattern">{options}</select>
  <label>Optional raw LEDS.LED</label>
  <textarea id="leds" placeholder="#00ff00 250ms pulse&#10;off 150ms none"></textarea>
  <button id="send">Send Push</button>
  <pre id="result">Ready</pre>
  <script>
    document.getElementById("send").addEventListener("click", async () => {{
      const body = {{
        device_token: document.getElementById("deviceToken").value,
        pattern: document.getElementById("pattern").value,
      }};
      const leds = document.getElementById("leds").value;
      if (leds.trim()) body.leds = leds;
      const secret = document.getElementById("secret").value;
      const response = await fetch("/v1/push", {{
        method: "POST",
        headers: {{
          "content-type": "application/json",
          ...(secret ? {{ "authorization": "Bearer " + secret }} : {{}})
        }},
        body: JSON.stringify(body)
      }});
      document.getElementById("result").textContent = JSON.stringify(await response.json(), null, 2);
    }});
  </script>
</body>
</html>"""


def main() -> int:
    host = os.environ.get("SIDEPULSE_SERVER_HOST", "127.0.0.1")
    port = int(os.environ.get("SIDEPULSE_SERVER_PORT", str(DEFAULT_PORT)))
    print(f"Serving SidePulse push server at http://{host}:{port}")
    uvicorn.run("server:app", host=host, port=port, log_level=os.environ.get("SIDEPULSE_LOG_LEVEL", "info"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
