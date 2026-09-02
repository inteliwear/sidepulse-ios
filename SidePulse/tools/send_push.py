#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def main() -> int:
    parser = argparse.ArgumentParser(description="Send a SidePulse push through the local push server.")
    parser.add_argument("--server", default=os.environ.get("SIDEPULSE_SERVER_URL", "http://127.0.0.1:8787"))
    parser.add_argument("--secret", default=os.environ.get("SIDEPULSE_SHARED_SECRET"))
    parser.add_argument("--device-token", default=os.environ.get("SIDEPULSE_DEVICE_TOKEN"))
    parser.add_argument("--pattern", default="green_pulse_2")
    parser.add_argument("--leds", help="Inline LEDS.LED text. If set, this wins over pattern in the app.")
    parser.add_argument("--file", type=Path, help="Path to a LEDS.LED file.")
    parser.add_argument("--payload", help="Extra JSON object merged into the APNs payload.")
    parser.add_argument("--alert", help="Optional visible notification body.")
    args = parser.parse_args()

    if args.leds and args.file:
        parser.error("Use either --leds or --file, not both")

    payload: dict[str, object] = {}
    if args.payload:
        loaded = json.loads(args.payload)
        if not isinstance(loaded, dict):
            parser.error("--payload must be a JSON object")
        payload = loaded

    body: dict[str, object] = {
        "pattern": args.pattern,
    }
    if args.device_token:
        body["device_token"] = args.device_token
    if args.alert:
        body["alert"] = args.alert
    if payload:
        body["payload"] = payload

    if args.leds is not None:
        body["leds"] = args.leds
    elif args.file:
        body["leds"] = args.file.read_text(encoding="utf-8")

    url = args.server.rstrip("/") + "/v1/push"
    headers = {"content-type": "application/json"}
    if args.secret:
        headers["authorization"] = f"Bearer {args.secret}"

    request = Request(url, data=json.dumps(body).encode("utf-8"), headers=headers, method="POST")

    try:
        with urlopen(request, timeout=20) as response:
            print(response.read().decode("utf-8"))
            return 0
    except HTTPError as exc:
        print(exc.read().decode("utf-8"), file=sys.stderr)
        return 1
    except URLError as exc:
        print(f"error: {exc.reason}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
