(function (global) {
  "use strict";

  const ERROR_NAMES = [
    "ok",
    "null-input",
    "too-long",
    "too-many-lines",
    "too-many-animation-lines",
    "syntax",
    "bad-color",
    "bad-index",
    "bad-time",
    "bad-brightness",
    "bad-repeat",
    "trailing-input",
  ];

  function nowMs() {
    const source = global.performance && typeof global.performance.now === "function"
      ? global.performance.now()
      : Date.now();
    return Math.floor(source);
  }

  function decodeParseResult(packed) {
    const error = (packed >>> 8) & 0xff;
    return {
      ok: (packed & 1) === 1,
      error,
      errorName: ERROR_NAMES[error] || `error-${error}`,
      line: (packed >>> 16) & 0xff,
      column: (packed >>> 24) & 0xff,
    };
  }

  function base64ToBytes(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  async function instantiateWasm(wasmUrl) {
    if (global.SDLED_WASM_BASE64) {
      const bytes = base64ToBytes(global.SDLED_WASM_BASE64);
      const result = await WebAssembly.instantiate(bytes, {});
      return result.instance;
    }

    if (global.location && global.location.protocol === "file:") {
      throw new Error("sdled_wasm_bundle.js is missing. Run websim/build-wasm-docker.sh or websim/build-wasm.sh, then reopen index.html.");
    }

    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        const result = await WebAssembly.instantiateStreaming(fetch(wasmUrl), {});
        return result.instance;
      } catch {
        // Some static servers do not send application/wasm. Fall through.
      }
    }

    const response = await fetch(wasmUrl);
    const bytes = await response.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, {});
    return result.instance;
  }

  function normalizeLedCount(ledCount) {
    return Number(ledCount) === 2 ? 2 : 8;
  }

  async function createSdLedController(options = {}) {
    const wasmUrl = typeof options === "string" ? options : options.wasmUrl || "./sdled.wasm";
    const ledCount = normalizeLedCount(typeof options === "string" ? 8 : options.ledCount);
    const instance = await instantiateWasm(wasmUrl);
    const exports = instance.exports;
    const memory = exports.memory;
    const inputPtr = exports.sdled_input_ptr();
    const outputPtr = exports.sdled_output_ptr();
    const encoder = new TextEncoder();

    exports.sdled_reset(ledCount, nowMs());

    return {
      ledCount,

      reset(t = 0) { exports.sdled_reset(ledCount, Math.floor(t)); },
      finished() { return Boolean(exports.sdled_finished(ledCount)); },

      parse(text, t = nowMs()) {
        const bytes = encoder.encode(text);
        if (bytes.length <= 512) {
          new Uint8Array(memory.buffer, inputPtr, 512).fill(0);
          new Uint8Array(memory.buffer, inputPtr, bytes.length).set(bytes);
          return decodeParseResult(exports.sdled_parse(ledCount, bytes.length, Math.floor(t)));
        }
        return decodeParseResult(exports.sdled_parse(ledCount, 513, Math.floor(t)));
      },

      step(t = nowMs()) {
        exports.sdled_step(ledCount, Math.floor(t));
        const view = new Uint8Array(memory.buffer, outputPtr, ledCount * 3);
        return new Uint8Array(view);
      },
    };
  }

  global.createSdLedController = createSdLedController;
})(globalThis);
