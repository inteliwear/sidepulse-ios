// Copyright (c) 2026 InteliWEAR LLC. MPL-2.0.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
// Brightest actual two-LED frame in the first two minutes. False means invalid
// source; callers should show a neutral device, not the firmware error flash.
bool SidePulseThumbnailSample(const uint8_t *source, size_t length, uint8_t *rgb);
#ifdef __cplusplus
}
#endif
