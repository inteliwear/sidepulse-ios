from __future__ import annotations

import asyncio
import copy
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from apns_client import APNsResponse  # noqa: E402
from server import app  # noqa: E402


class FakeAPNsClient:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []

    async def send(
        self,
        device_token: str,
        payload: dict[str, object],
        *,
        headers: dict[str, str] | None = None,
    ) -> APNsResponse:
        await asyncio.sleep(0)
        self.calls.append(
            {
                "device_token": device_token,
                "payload": copy.deepcopy(payload),
                "headers": dict(headers or {}),
            }
        )
        return APNsResponse(status_code=200, apns_id="test-apns-id", body={"sent": True})

    async def aclose(self) -> None:
        pass


class ServerTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.fake = FakeAPNsClient()
        app.state.apns_client = self.fake
        self.env = patch.dict(
            os.environ,
            {
                "SIDEPULSE_SHARED_SECRET": "secret",
                "SIDEPULSE_DEVICE_TOKEN": "env-device-token",
            },
            clear=False,
        )
        self.env.start()

    def tearDown(self) -> None:
        self.env.stop()
        if hasattr(app.state, "apns_client"):
            delattr(app.state, "apns_client")

    def test_requires_bearer_auth(self) -> None:
        with TestClient(app) as client:
            response = client.post("/v1/push", json={"pattern": "green_pulse_2"})

        self.assertEqual(response.status_code, 401)
        self.assertEqual(self.fake.calls, [])

    def test_friendly_pattern_envelope(self) -> None:
        with TestClient(app) as client:
            response = client.post(
                "/v1/push",
                headers={"authorization": "Bearer secret"},
                json={"pattern": "green_pulse_2"},
            )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["known_pattern"])
        self.assertEqual(len(self.fake.calls), 1)
        call = self.fake.calls[0]
        self.assertEqual(call["device_token"], "env-device-token")
        self.assertEqual(call["payload"]["pattern"], "green_pulse_2")
        self.assertEqual(call["payload"]["aps"], {"content-available": 1})
        self.assertEqual(call["headers"]["apns-push-type"], "background")
        self.assertEqual(call["headers"]["apns-priority"], "5")

    def test_apns_header_mapping(self) -> None:
        with TestClient(app) as client:
            response = client.post(
                "/v1/push",
                headers={"authorization": "Bearer secret"},
                json={
                    "device_token": "explicit-token",
                    "pattern": "success",
                    "apns": {
                        "push_type": "alert",
                        "priority": 10,
                        "collapse_id": "pulse-status",
                        "expiration": "0",
                    },
                },
            )

        self.assertEqual(response.status_code, 200)
        call = self.fake.calls[0]
        self.assertEqual(call["device_token"], "explicit-token")
        self.assertEqual(call["headers"]["apns-push-type"], "alert")
        self.assertEqual(call["headers"]["apns-priority"], "10")
        self.assertEqual(call["headers"]["apns-collapse-id"], "pulse-status")
        self.assertEqual(call["headers"]["apns-expiration"], "0")

    def test_leds_led_payload_alias(self) -> None:
        with TestClient(app) as client:
            response = client.post(
                "/v1/push",
                headers={"authorization": "Bearer secret"},
                json={"LEDS.LED": "#00ff00 280ms pulse\n"},
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.fake.calls[0]["payload"]["leds"], "#00ff00 280ms pulse\n")

    def test_friendly_led_payload_decodes_escaped_newlines(self) -> None:
        with TestClient(app) as client:
            response = client.post(
                "/v1/push",
                headers={"authorization": "Bearer secret"},
                json={"leds": r"off\n#00ff00 280ms pulse\n"},
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.fake.calls[0]["payload"]["leds"], "off\n#00ff00 280ms pulse\n")

    def test_friendly_led_payload_line_limit_uses_decoded_newlines(self) -> None:
        with TestClient(app) as client:
            response = client.post(
                "/v1/push",
                headers={"authorization": "Bearer secret"},
                json={"leds": r"\n".join(["off"] * 21)},
            )

        self.assertEqual(response.status_code, 400)
        self.assertIn("max is 20", response.text)
        self.assertEqual(self.fake.calls, [])

    def test_old_leds_txt_key_is_not_promoted_to_led_text(self) -> None:
        with TestClient(app) as client:
            response = client.post(
                "/v1/push",
                headers={"authorization": "Bearer secret"},
                json={"LEDS.TXT": "#00ff00 280ms pulse\n"},
            )

        self.assertEqual(response.status_code, 200)
        payload = self.fake.calls[0]["payload"]
        self.assertNotIn("leds", payload)
        self.assertEqual(payload["LEDS.TXT"], "#00ff00 280ms pulse\n")

    def test_friendly_led_payload_validates_line_limit(self) -> None:
        with TestClient(app) as client:
            response = client.post(
                "/v1/push",
                headers={"authorization": "Bearer secret"},
                json={"leds": "\n".join(["off"] * 21)},
            )

        self.assertEqual(response.status_code, 400)
        self.assertIn("max is 20", response.text)
        self.assertEqual(self.fake.calls, [])

    def test_raw_payload_passthrough(self) -> None:
        raw_payload = {
            "aps": {"content-available": 1},
            "custom": {"nested": [1, 2, 3]},
            "pattern": "working",
        }

        with TestClient(app) as client:
            response = client.post(
                "/v1/push/raw?device_token=query-token",
                headers={
                    "authorization": "Bearer secret",
                    "x-apns-push-type": "background",
                    "x-apns-priority": "5",
                },
                json=raw_payload,
            )

        self.assertEqual(response.status_code, 200)
        call = self.fake.calls[0]
        self.assertEqual(call["device_token"], "query-token")
        self.assertEqual(call["payload"], raw_payload)
        self.assertEqual(call["headers"]["apns-push-type"], "background")
        self.assertEqual(call["headers"]["apns-priority"], "5")


class ConcurrentServerTestCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.fake = FakeAPNsClient()
        app.state.apns_client = self.fake
        self.env = patch.dict(
            os.environ,
            {
                "SIDEPULSE_SHARED_SECRET": "secret",
                "SIDEPULSE_DEVICE_TOKEN": "env-device-token",
            },
            clear=False,
        )
        self.env.start()

    async def asyncTearDown(self) -> None:
        self.env.stop()
        if hasattr(app.state, "apns_client"):
            delattr(app.state, "apns_client")

    async def test_mocked_concurrent_sends(self) -> None:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            responses = await asyncio.gather(
                *[
                    client.post(
                        "/v1/push",
                        headers={"authorization": "Bearer secret"},
                        json={"pattern": "green_pulse_2"},
                    )
                    for _ in range(40)
                ]
            )

        self.assertTrue(all(response.status_code == 200 for response in responses))
        self.assertEqual(len(self.fake.calls), 40)
