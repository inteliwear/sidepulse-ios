#include "SdLedController.h"

#include <stdint.h>

namespace {

constexpr uint8_t kSidePulseLedCount = 8;
constexpr uint8_t kPulseDotLedCount = 2;
constexpr uint8_t kMaxLedCount = kSidePulseLedCount;

sdled::LedController<kSidePulseLedCount, 20> controller8;
sdled::LedController<kPulseDotLedCount, 20> controller2;
char inputBuffer[sdled::LedController<8>::kMaxInputBytes];
sdled::Rgb pixels8[kSidePulseLedCount];
sdled::Rgb pixels2[kPulseDotLedCount];
sdled::Rgb outputPixels[kMaxLedCount];
uint8_t initialized8 = 0;
uint8_t initialized2 = 0;
sdled::ParseResult lastParseResult8{true, 0, 0, sdled::kParseOk};
sdled::ParseResult lastParseResult2{true, 0, 0, sdled::kParseOk};

uint32_t normalizeLedCount(uint32_t ledCount) {
  return ledCount == kPulseDotLedCount ? kPulseDotLedCount : kSidePulseLedCount;
}

void copyPixels(const sdled::Rgb *source, uint8_t count) {
  for (uint8_t i = 0; i < count; ++i) {
    outputPixels[i] = source[i];
  }
}

void ensureInitialized(uint32_t ledCount, uint32_t nowMs) {
  if (normalizeLedCount(ledCount) == kPulseDotLedCount) {
    if (!initialized2) {
      controller2.reset();
      controller2.step(nowMs, pixels2);
      copyPixels(pixels2, kPulseDotLedCount);
      initialized2 = 1;
    }
    return;
  }

  if (!initialized8) {
    controller8.reset();
    controller8.step(nowMs, pixels8);
    copyPixels(pixels8, kSidePulseLedCount);
    initialized8 = 1;
  }
}

uint32_t packResult(sdled::ParseResult result) {
  return (result.ok ? 1u : 0u) |
         (static_cast<uint32_t>(result.error) << 8) |
         (static_cast<uint32_t>(result.line) << 16) |
         (static_cast<uint32_t>(result.column) << 24);
}

} // namespace

extern "C" __attribute__((visibility("default"))) uintptr_t sdled_input_ptr() {
  return reinterpret_cast<uintptr_t>(inputBuffer);
}

extern "C" __attribute__((visibility("default"))) uintptr_t sdled_output_ptr() {
  return reinterpret_cast<uintptr_t>(outputPixels);
}

extern "C" __attribute__((visibility("default"))) void sdled_reset(uint32_t ledCount,
                                                                    uint32_t nowMs) {
  if (normalizeLedCount(ledCount) == kPulseDotLedCount) {
    controller2.reset();
    controller2.step(nowMs, pixels2);
    copyPixels(pixels2, kPulseDotLedCount);
    lastParseResult2 = sdled::ParseResult{true, 0, 0, sdled::kParseOk};
    initialized2 = 1;
    return;
  }

  controller8.reset();
  controller8.step(nowMs, pixels8);
  copyPixels(pixels8, kSidePulseLedCount);
  lastParseResult8 = sdled::ParseResult{true, 0, 0, sdled::kParseOk};
  initialized8 = 1;
}

extern "C" __attribute__((visibility("default"))) uint32_t sdled_parse(uint32_t ledCount,
                                                                       uint32_t length,
                                                                       uint32_t nowMs) {
  ensureInitialized(ledCount, nowMs);
  if (length > sdled::LedController<8>::kMaxInputBytes) {
    length = sdled::LedController<8>::kMaxInputBytes + 1u;
  }

  if (normalizeLedCount(ledCount) == kPulseDotLedCount) {
    lastParseResult2 = controller2.parse(inputBuffer, static_cast<uint16_t>(length), nowMs);
    return packResult(lastParseResult2);
  }

  lastParseResult8 = controller8.parse(inputBuffer, static_cast<uint16_t>(length), nowMs);
  return packResult(lastParseResult8);
}

extern "C" __attribute__((visibility("default"))) void sdled_step(uint32_t ledCount,
                                                                  uint32_t nowMs) {
  ensureInitialized(ledCount, nowMs);
  if (normalizeLedCount(ledCount) == kPulseDotLedCount) {
    controller2.step(nowMs, pixels2);
    copyPixels(pixels2, kPulseDotLedCount);
    return;
  }

  controller8.step(nowMs, pixels8);
  copyPixels(pixels8, kSidePulseLedCount);
}

extern "C" __attribute__((visibility("default"))) uint32_t sdled_last_parse_result(uint32_t ledCount) {
  return packResult(normalizeLedCount(ledCount) == kPulseDotLedCount
                        ? lastParseResult2
                        : lastParseResult8);
}

extern "C" __attribute__((visibility("default"))) uint32_t sdled_finished(uint32_t ledCount) {
  return normalizeLedCount(ledCount) == kPulseDotLedCount
      ? controller2.finished() : controller8.finished();
}
