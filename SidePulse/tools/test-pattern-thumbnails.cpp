// Copyright (c) 2026 InteliWEAR LLC. MPL-2.0.
#include "../SidePulse/PatternThumbnailSampler.h"
#include <cassert>
#include <cstring>
#include <cstdio>
#include <string>
static void sample(const char *text, uint8_t (&rgb)[6]) {
    assert(SidePulseThumbnailSample(reinterpret_cast<const uint8_t *>(text), strlen(text), rgb));
}
int main() {
    uint8_t rgb[6];
    sample("off\n#FF0000 #FF0000 280ms pulse\noff 160ms none\nrepeat 2\n", rgb);
    assert(rgb[0] >= 254 && rgb[3] >= 254 && rgb[1] == 0 && rgb[2] == 0);
    sample("off\n#00FF00 #00FF00 1400ms pulse\noff 400ms none\nrepeat\n", rgb);
    assert(rgb[1] >= 254 && rgb[4] >= 254 && rgb[0] == 0 && rgb[2] == 0);
    sample("off\n#FF4600 #0066FF 10000ms none\nrepeat\n", rgb);
    assert(rgb[0] == 255 && rgb[1] == 70 && rgb[2] == 0 && rgb[3] == 0 && rgb[4] == 102 && rgb[5] == 255);
    sample("off\nbrightness 40\n#FF00FF 500ms pulse\n", rgb);
    assert(rgb[0] == 40 && rgb[2] == 40 && rgb[1] == 0 && rgb[3] == 40 && rgb[5] == 40);
    sample("off\n0:#12ABEF 1:#ED4321 500ms none 3s\n", rgb);
    assert(rgb[0] == 0x12 && rgb[1] == 0xAB && rgb[2] == 0xEF && rgb[3] == 0xED && rgb[4] == 0x43 && rgb[5] == 0x21);
    sample("off", rgb);
    for (auto c : rgb) assert(c == 0);
    const char *bad = "bad color";
    assert(!SidePulseThumbnailSample(reinterpret_cast<const uint8_t *>(bad), strlen(bad), rgb));
    for (auto c : rgb) assert(c == 0);
    const std::string large(513, 'x');
    assert(!SidePulseThumbnailSample(reinterpret_cast<const uint8_t *>(large.data()), large.size(), rgb));
    puts("Thumbnail sampling: pulse peaks, custom colors, INIT.LED brightness, indexed/delayed commands, off, and malformed/oversized source passed.");
}
