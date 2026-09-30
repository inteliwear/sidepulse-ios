#!/bin/sh
set -eu
cd "$(dirname "$0")"
: "${WASM_CLANG:=/opt/homebrew/opt/llvm/bin/clang++}"
: "${WASM_LD:=/opt/homebrew/opt/lld/bin/wasm-ld}"
"$WASM_CLANG" --target=wasm32-unknown-unknown-wasm -std=c++17 -Oz \
  -ffreestanding -fno-builtin -fno-exceptions -fno-rtti -fvisibility=hidden \
  -nostdlib -fuse-ld="$WASM_LD" sdled_wasm.cpp \
  -Wl,--no-entry -Wl,--export-memory \
  -Wl,--export=sdled_input_ptr -Wl,--export=sdled_output_ptr \
  -Wl,--export=sdled_reset -Wl,--export=sdled_parse -Wl,--export=sdled_step \
  -Wl,--export=sdled_last_parse_result -Wl,--export=sdled_finished \
  -o ../../SidePulse/PatternPreviewWeb/sdled.wasm

python3 ../prepare_pattern_preview.py
