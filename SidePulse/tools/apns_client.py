from __future__ import annotations

import base64
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils


MAX_LEDS_BYTES = 512
MAX_LEDS_LINES = 20
APNS_JWT_REFRESH_SECONDS = 50 * 60


class APNsConfigError(RuntimeError):
    pass


class LEDPayloadError(ValueError):
    pass


@dataclass(frozen=True)
class APNsConfig:
    team_id: str
    key_id: str
    auth_key_path: Path
    bundle_id: str
    environment: str = "sandbox"

    @classmethod
    def from_env(cls) -> "APNsConfig":
        missing = [
            name
            for name in ("APNS_TEAM_ID", "APNS_KEY_ID", "APNS_AUTH_KEY", "APNS_BUNDLE_ID")
            if not os.environ.get(name)
        ]
        if missing:
            raise APNsConfigError(f"Missing environment variables: {', '.join(missing)}")

        return cls(
            team_id=os.environ["APNS_TEAM_ID"],
            key_id=os.environ["APNS_KEY_ID"],
            auth_key_path=Path(os.environ["APNS_AUTH_KEY"]).expanduser(),
            bundle_id=os.environ["APNS_BUNDLE_ID"],
            environment=os.environ.get("APNS_ENV", "sandbox"),
        )

    @property
    def host(self) -> str:
        if self.environment.lower() in {"prod", "production"}:
            return "api.push.apple.com"
        return "api.sandbox.push.apple.com"


@dataclass(frozen=True)
class APNsResponse:
    status_code: int
    apns_id: str | None
    body: dict[str, Any] | str

    @property
    def ok(self) -> bool:
        return 200 <= self.status_code < 300


class APNsProviderTokenCache:
    def __init__(self, config: APNsConfig) -> None:
        self.config = config
        self._private_key: ec.EllipticCurvePrivateKey | None = None
        self._token: str | None = None
        self._refresh_at = 0

    def token(self) -> str:
        now = int(time.time())
        if self._token and now < self._refresh_at:
            return self._token

        private_key = self._load_private_key()
        self._token = make_provider_token(self.config, issued_at=now, private_key=private_key)
        self._refresh_at = now + APNS_JWT_REFRESH_SECONDS
        return self._token

    def _load_private_key(self) -> ec.EllipticCurvePrivateKey:
        if self._private_key is not None:
            return self._private_key

        private_key = serialization.load_pem_private_key(
            self.config.auth_key_path.read_bytes(),
            password=None,
        )

        if not isinstance(private_key, ec.EllipticCurvePrivateKey):
            raise APNsConfigError("APNs auth key must be an EC private key")

        self._private_key = private_key
        return private_key


class APNsClient:
    def __init__(
        self,
        config: APNsConfig,
        *,
        client: httpx.AsyncClient | None = None,
        timeout: float = 10.0,
    ) -> None:
        self.config = config
        self._token_cache = APNsProviderTokenCache(config)
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            http2=True,
            timeout=httpx.Timeout(timeout),
            limits=httpx.Limits(max_connections=1000, max_keepalive_connections=250),
        )

    async def __aenter__(self) -> "APNsClient":
        return self

    async def __aexit__(self, *_: object) -> None:
        await self.aclose()

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def send(
        self,
        device_token: str,
        payload: dict[str, Any],
        *,
        headers: dict[str, str] | None = None,
    ) -> APNsResponse:
        token = device_token.strip()
        if not token:
            raise ValueError("Missing device token")

        request_headers = {
            "authorization": f"bearer {self._token_cache.token()}",
            "apns-topic": self.config.bundle_id,
            "apns-push-type": "background",
            "apns-priority": "5",
        }
        if headers:
            request_headers.update({key: str(value) for key, value in headers.items() if value is not None})

        url = f"https://{self.config.host}/3/device/{token}"
        response = await self._client.post(url, headers=request_headers, json=payload)

        try:
            body: dict[str, Any] | str = response.json()
        except json.JSONDecodeError:
            body = response.text

        return APNsResponse(
            status_code=response.status_code,
            apns_id=response.headers.get("apns-id"),
            body=body,
        )


def validate_leds_text(leds_text: str) -> None:
    if not leds_text.strip():
        raise LEDPayloadError("LEDS.LED payload is empty")

    byte_count = len(leds_text.encode("utf-8"))
    if byte_count > MAX_LEDS_BYTES:
        raise LEDPayloadError(f"LEDS.LED payload is {byte_count} bytes; max is {MAX_LEDS_BYTES}")

    line_count = len(leds_text.splitlines()) or 1
    if line_count > MAX_LEDS_LINES:
        raise LEDPayloadError(f"LEDS.LED payload has {line_count} lines; max is {MAX_LEDS_LINES}")


def normalize_leds_text(leds_text: str) -> str:
    return decode_simple_escapes(leds_text)


def decode_simple_escapes(text: str) -> str:
    output: list[str] = []
    index = 0
    while index < len(text):
        char = text[index]
        if char != "\\" or index + 1 >= len(text):
            output.append(char)
            index += 1
            continue

        next_char = text[index + 1]
        if next_char == "n":
            output.append("\n")
            index += 2
        elif next_char == "r":
            output.append("\r")
            index += 2
        elif next_char == "t":
            output.append("\t")
            index += 2
        elif next_char == "\\":
            output.append("\\")
            index += 2
        else:
            output.append(char)
            index += 1
    return "".join(output)


def make_provider_token(
    config: APNsConfig,
    issued_at: int | None = None,
    *,
    private_key: ec.EllipticCurvePrivateKey | None = None,
) -> str:
    issued_at = issued_at or int(time.time())
    private_key = private_key or serialization.load_pem_private_key(
        config.auth_key_path.read_bytes(),
        password=None,
    )

    if not isinstance(private_key, ec.EllipticCurvePrivateKey):
        raise APNsConfigError("APNs auth key must be an EC private key")

    header = {"alg": "ES256", "kid": config.key_id}
    claims = {"iss": config.team_id, "iat": issued_at}
    signing_input = b".".join(
        [
            _b64url_json(header),
            _b64url_json(claims),
        ]
    )
    der_signature = private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r_value, s_value = utils.decode_dss_signature(der_signature)
    raw_signature = r_value.to_bytes(32, "big") + s_value.to_bytes(32, "big")
    return signing_input.decode("ascii") + "." + _b64url(raw_signature).decode("ascii")


async def send_leds_push(
    config: APNsConfig,
    device_token: str,
    leds_text: str,
    *,
    alert: str | None = None,
) -> APNsResponse:
    leds_text = normalize_leds_text(leds_text)
    validate_leds_text(leds_text)

    push_type = "alert" if alert else "background"
    priority = "10" if alert else "5"
    aps: dict[str, Any] = {"content-available": 1}
    if alert:
        aps["alert"] = {"title": "SidePulse", "body": alert}
        aps["sound"] = "default"

    payload = {
        "aps": aps,
        "leds": leds_text,
    }
    headers = {
        "apns-push-type": push_type,
        "apns-priority": priority,
    }

    async with APNsClient(config) as client:
        return await client.send(device_token, payload, headers=headers)


def _b64url_json(value: dict[str, Any]) -> bytes:
    return _b64url(json.dumps(value, separators=(",", ":")).encode("utf-8"))


def _b64url(value: bytes) -> bytes:
    return base64.urlsafe_b64encode(value).rstrip(b"=")
