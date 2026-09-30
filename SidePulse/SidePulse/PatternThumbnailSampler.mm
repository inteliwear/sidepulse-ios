// Copyright (c) 2026 InteliWEAR LLC. MPL-2.0.
#include "PatternThumbnailSampler.h"
#include "../tools/preview-wasm/SdLedController.h"

bool SidePulseThumbnailSample(const uint8_t *source, size_t length, uint8_t *rgb) {
    for (int i = 0; i < 6; ++i) rgb[i] = 0;
    if (length > 512 || (!source && length)) return false;
    sdled::LedController<2, 20> controller;
    controller.reset();
    const auto result = controller.parse(reinterpret_cast<const char *>(source), static_cast<uint16_t>(length), 0);
    if (!result.ok) return false;
    unsigned best = 0;
    for (uint32_t time = 0; time <= 120000; time += 8) {
        sdled::Rgb pixels[2];
        controller.step(time, pixels);
        unsigned score = 0;
        for (const auto &pixel : pixels) score += pixel.r + pixel.g + pixel.b;
        if (score > best) {
            best = score;
            for (int i = 0; i < 2; ++i) {
                rgb[i * 3] = pixels[i].r;
                rgb[i * 3 + 1] = pixels[i].g;
                rgb[i * 3 + 2] = pixels[i].b;
            }
        }
        if (controller.finished() || best == 1530) break;
    }
    return true;
}
