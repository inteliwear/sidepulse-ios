from __future__ import annotations

from dataclasses import dataclass, asdict


@dataclass(frozen=True)
class LEDPattern:
    name: str
    display_name: str
    detail: str
    leds: str

    @property
    def byte_count(self) -> int:
        return len(self.leds.encode("utf-8"))

    def as_public_dict(self) -> dict[str, object]:
        payload = asdict(self)
        payload["byte_count"] = self.byte_count
        return payload


PATTERNS: dict[str, LEDPattern] = {
    "off": LEDPattern(
        name="off",
        display_name="Off",
        detail="Clear the LEDs",
        leds="off\n",
    ),
    "green_pulse_2": LEDPattern(
        name="green_pulse_2",
        display_name="Two Green Pulses",
        detail="Two quick confirmation pulses",
        leds="#00ff00 280ms pulse\noff 160ms none\n#00ff00 280ms pulse\noff 320ms none\n",
    ),
    "success": LEDPattern(
        name="success",
        display_name="Success",
        detail="Soft green success glow",
        leds="#00ff66 450ms cosine\noff 160ms none\n",
    ),
    "error": LEDPattern(
        name="error",
        display_name="Error",
        detail="Red attention blink",
        leds="#ff1f3d 120ms none\noff 120ms none\nrepeat 3\n",
    ),
    "working": LEDPattern(
        name="working",
        display_name="Working",
        detail="Blue activity pulse",
        leds="#0066ff 900ms pulse\n#00ccff 900ms pulse\nrepeat\n",
    ),
    "waiting": LEDPattern(
        name="waiting",
        display_name="Waiting",
        detail="Amber waiting breath",
        leds="#ffaa00 1.2s pulse\noff 500ms none\nrepeat\n",
    ),
    "white_breathe": LEDPattern(
        name="white_breathe",
        display_name="White Breathe",
        detail="Soft neutral breathing",
        leds="#404040 1.4s pulse\noff 400ms none\nrepeat\n",
    ),
}


def pattern_names() -> list[str]:
    return list(PATTERNS)
