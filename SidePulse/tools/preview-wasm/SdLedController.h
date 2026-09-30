#pragma once

/*
  sdled::LedController
  ====================

  Header-only LED animation controller for small embedded targets.

  Design constraints:
  - No dynamic allocation.
  - No floating point.
  - No STL containers.
  - No exceptions or RTTI required.
  - No platform, hardware, browser, or WASM APIs.
  - Compiled animation storage is owned by the controller object, not the call stack.
  - LED count is a compile-time template parameter. The default is 8:
      sdled::LedController<> leds;
    A 2 LED target can use:
      sdled::LedController<2> leds;
    Firmware builds ignore out-of-range LED targets by default so shared scripts
    remain portable. Diagnostic/simulator builds can instantiate with:
      sdled::LedController<8, 20, false> leds;
    to surface out-of-range targets as parse errors.

  Call reset() once before first use. parse() replaces the current animation
  only when the entire input is valid. step() writes brightness-scaled RGB
  values into the caller-owned output array. Higher-precision output drivers can
  use stepUnscaled() and brightness() to combine scaling with their final conversion.

  LED Animation DSL
  =================

  Limits:
  - Input is at most 512 bytes.
  - Input is at most MaxLines physical lines. MaxLines defaults to 20.
  - Lines are evaluated as animation steps from top to bottom.
  - Blank lines and comment lines starting with ';', '//', or '# ' are ignored.

  Colors:
  - #RRGGBB sets every LED to one color.
  - off is an alias for #000000.
  - #RRGGBB #RRGGBB ... assigns colors by LED index. LEDs past the list turn off.
    Colors past the compiled LED count are parsed and ignored.
  - N:#RRGGBB assigns a specific LED index. Indexes outside the compiled LED
    count are parsed and ignored. Unmentioned LEDs keep their state.
  - Multiple indexed assignments may appear on one line.
  - If one LED is assigned more than once on a line, the last assignment wins.

  Brightness:
  - brightness N sets output brightness, where N is 0..255.
  - Each successful parse starts with brightness 255 unless brightness N appears.
  - Brightness affects values written by step(); animation state remains full RGB.

  Timing:
  - A color assignment may be followed by duration, easing, and delay:
      #ff00ff 330ms
      #ff00ff ease-in
      #ff00ff 0.33s ease-in
      #ff00ff 0.33s ease-in 1s
      #ff00ff pulse 1s
      0:#ff00ff 0.33s ease-in 0s; 1:#00ff00 0.5s linear 250ms
  - Durations and delays accept ms or s, up to 65535 ms.
  - Decimal seconds are allowed, e.g. 0.33s.
  - An easing name without a duration uses the default 330 ms duration.
  - A line finishes after the longest delay + duration on that line.
  - A line with no duration or delay lasts one 60 Hz frame.

  Easing:
  - Supported easing names: linear, ease, ease-in, ease-out, ease-in-out,
    cosine, pulse, none.
  - Missing easing defaults to ease when a duration is present.
  - none jumps to the target after delay, then holds until the line finishes.
  - pulse moves from the line's start color to the target color and back to the
    start color over one duration. The target is the peak, not the final hold.
  - All easing uses fixed-point integer math.

  Roll:
  - roll DURATION [EASING] rotates the current LED state right by one full
    wraparound loop over DURATION. roll-right is an explicit alias.
  - roll-left DURATION [EASING] rotates left by one full wraparound loop.
  - Missing easing defaults to linear.

  Repeat:
  - repeat loops forever from the first animation line.
  - repeat N runs the animation before the repeat marker N total times.
  - Finite repeat continues with any animation lines after the repeat marker.
  - If no lines follow the repeat marker, finite repeat holds the final state.

  Parse behavior:
  - parse() commits only if the entire input is valid.
  - On parse failure, parse() returns an error and step() blinks all LEDs red
    six times with 150 ms on/off phases. The previous animation is stopped,
    and LEDs hold off after the error blink finishes.
  - After a successful parse with animation lines, the next step starts from
    line 1 using the current visible LEDs as the transition start colors.
  - A successful parse with only brightness/comment/blank lines stops animation
    and holds the current visible state.

  Examples:

      # all LEDs white
      #ffffff

      # all LEDs off
      #000000

      # same as #000000
      off

      # first three LEDs red/green/blue, remaining LEDs off
      #ff0000 #00ff00 #0000ff

      # specific LEDs only; unmentioned LEDs hold their current state
      0:#ffffff 2:#ff00ee 7:#0040ff

      # set brightness to half output
      brightness 128

      # fade all LEDs to purple over 330 ms using default ease
      #ff00ff 330ms

      # same transition using seconds
      #ff00ff 0.33s

      # fade to purple with CSS-like ease-in
      #ff00ff 0.33s ease-in

      # same easing using the default 330 ms duration
      #ff00ff ease-in

      # pulse to purple and back to the starting color over 1.4 seconds
      #ff00ff 1.4s pulse

      # pulse using the default 330 ms duration
      #ff00ff pulse

      # soft breathing loop: pulse up/down, pause off, repeat
      #404040 1.4s pulse
      off 400ms none
      repeat

      # wait 1 second, then fade to purple for 330 ms
      #ff00ff 0.33s ease-in 1s

      # LED 0 starts immediately, LED 1 starts after 250 ms
      0:#ff00ff 0.33s ease-in 0s; 1:#00ff00 0.33s linear 250ms

      # one-line chase step: only LED 3 changes; all others hold
      3:#ffffff 80ms none

      # 3-step chase that loops forever
      0:#ffffff 80ms none
      1:#ffffff 80ms none
      2:#ffffff 80ms none
      repeat

      # run a red/green blink 10 total times, then hold final state
      #ff0000 200ms none
      #00ff00 200ms none
      repeat 10

      # run a red/green blink twice, then turn off
      #000000
      #ff0000 2000ms ease
      #00ff00 2000ms ease
      repeat 2
      #000000

      # stagger LEDs with one line
      0:#ff0000 150ms ease 0ms; 1:#ff8000 150ms ease 50ms; 2:#ffff00 150ms ease 100ms; 3:#00ff00 150ms ease 150ms

      # duplicate LED assignment: last one wins
      0:#ff0000 1s; 0:#0000ff 1s

      # smoothly roll the current visible state
      roll 2s linear
*/

#include <stddef.h>
#include <stdint.h>

namespace sdled {

struct Rgb {
  uint8_t r;
  uint8_t g;
  uint8_t b;
};

enum ParseError : uint8_t {
  kParseOk = 0,
  kParseNullInput = 1,
  kParseTooLong = 2,
  kParseTooManyLines = 3,
  kParseTooManyAnimationLines = 4,
  kParseSyntax = 5,
  kParseBadColor = 6,
  kParseBadIndex = 7,
  kParseBadTime = 8,
  kParseBadBrightness = 9,
  kParseBadRepeat = 10,
  kParseTrailingInput = 11
};

struct ParseResult {
  bool ok;
  uint8_t line;
  uint8_t column;
  uint8_t error;
};

template <uint8_t LedCount = 8, uint8_t MaxLines = 20, bool IgnoreOutOfRange = true>
class LedController {
public:
  static constexpr uint16_t kMaxInputBytes = 512;
  static constexpr uint16_t kFrameMs = 17;
  static constexpr uint16_t kDefaultDurationMs = 330;
  static constexpr uint16_t kErrorBlinkPhaseMs = 150;
  static constexpr uint8_t kErrorBlinkCount = 6;

  void reset(Rgb color = Rgb{0, 0, 0}) {
    brightness_ = 255;
    lineCount_ = 0;
    currentLine_ = 0;
    repeatInfinite_ = 0;
    repeatLimit_ = 1;
    repeatRuns_ = 0;
    repeatIndex_ = 0;
    hasRepeat_ = 0;
    errorBlinkActive_ = 0;
    parsing_ = 0;
    errorBlinkStartMs_ = 0;
    holding_ = 1;
    lineStartMs_ = 0;
    clearLines(lines_, MaxLines);
    for (uint8_t i = 0; i < LedCount; ++i) {
      current_[i] = color;
      lineStart_[i] = color;
    }
  }

  ParseResult parse(const char *text, uint16_t length, uint32_t nowMs) {
    static_assert(LedCount > 0, "LedCount must be greater than zero");
    static_assert(MaxLines > 0, "MaxLines must be greater than zero");

    updateTo(nowMs);

    if (text == nullptr && length != 0) {
      return fail(error(0, 0, kParseNullInput), nowMs);
    }
    if (length > kMaxInputBytes) {
      return fail(error(0, 0, kParseTooLong), nowMs);
    }

    parsing_ = 1;
    clearLines(lines_, MaxLines);
    uint8_t parsedLineCount = 0;
    uint8_t physicalLineCount = 0;
    uint8_t parsedRepeat = 0;
    uint8_t parsedRepeatInfinite = 0;
    uint16_t parsedRepeatLimit = 1;
    uint8_t parsedRepeatIndex = 0;
    uint8_t parsedBrightness = 255;

    uint16_t offset = 0;
    while (offset < length) {
      const uint16_t lineStart = offset;
      while (offset < length && text[offset] != '\n' && text[offset] != '\r') {
        if (text[offset] == '\0') {
          return fail(error(physicalLineCount + 1u,
                            static_cast<uint8_t>(offset - lineStart + 1u),
                            kParseSyntax),
                      nowMs);
        }
        ++offset;
      }
      const uint16_t lineLength = static_cast<uint16_t>(offset - lineStart);
      if (offset < length) {
        const char newline = text[offset++];
        if (newline == '\r' && offset < length && text[offset] == '\n') {
          ++offset;
        }
      }

      ++physicalLineCount;
      if (physicalLineCount > MaxLines) {
        return fail(error(physicalLineCount, 1, kParseTooManyLines), nowMs);
      }

      LineCursor cursor{text + lineStart, lineLength, 0, physicalLineCount};
      ParseResult lineResult = parsePhysicalLine(cursor,
                                                 lines_,
                                                 parsedLineCount,
                                                 parsedRepeat,
                                                 parsedRepeatInfinite,
                                                 parsedRepeatLimit,
                                                 parsedRepeatIndex,
                                                 parsedBrightness);
      if (!lineResult.ok) {
        return fail(lineResult, nowMs);
      }
    }

    if (parsedRepeat && parsedRepeatIndex == 0) {
      return fail(error(physicalLineCount == 0 ? 1 : physicalLineCount, 1, kParseBadRepeat), nowMs);
    }

    errorBlinkActive_ = 0;
    brightness_ = parsedBrightness;
    lineCount_ = parsedLineCount;
    repeatInfinite_ = parsedRepeatInfinite;
    repeatLimit_ = parsedRepeat ? parsedRepeatLimit : 1;
    repeatRuns_ = 0;
    repeatIndex_ = parsedRepeatIndex;
    hasRepeat_ = parsedRepeat;
    currentLine_ = 0;
    lineStartMs_ = nowMs;
    for (uint8_t i = 0; i < LedCount; ++i) {
      lineStart_[i] = current_[i];
    }
    holding_ = lineCount_ == 0 ? 1 : 0;
    parsing_ = 0;

    return ok();
  }

  void step(uint32_t nowMs, Rgb (&out)[LedCount]) {
    stepUnscaled(nowMs, out);
    for (uint8_t i = 0; i < LedCount; ++i) {
      out[i] = scale(out[i]);
    }
  }

  // Advance exactly as step() does, including error blinks, without quantizing
  // brightness into an 8-bit intermediate. The caller must apply brightness().
  void stepUnscaled(uint32_t nowMs, Rgb (&out)[LedCount]) {
    if (parsing_) {
      for (uint8_t i = 0; i < LedCount; ++i) {
        out[i] = current_[i];
      }
      return;
    }

    if (errorBlinkActive_) {
      const uint32_t elapsed = nowMs - errorBlinkStartMs_;
      const uint32_t totalMs = static_cast<uint32_t>(kErrorBlinkPhaseMs) * kErrorBlinkCount * 2u;
      if (elapsed < totalMs) {
        const bool redPhase = ((elapsed / kErrorBlinkPhaseMs) & 1u) == 0u;
        const Rgb color = redPhase ? Rgb{255, 0, 0} : Rgb{0, 0, 0};
        for (uint8_t i = 0; i < LedCount; ++i) {
          out[i] = color;
        }
        return;
      }
      errorBlinkActive_ = 0;
    }

    updateTo(nowMs);
    for (uint8_t i = 0; i < LedCount; ++i) {
      out[i] = current_[i];
    }
  }

  uint8_t brightness() const {
    return brightness_;
  }

  // Browser preview: completion also includes a final lit hold.
  bool finished() const {
    return !parsing_ && !errorBlinkActive_ && (holding_ || lineCount_ == 0);
  }

  bool idleAndDark() const {
    if (parsing_ || errorBlinkActive_ || (!holding_ && lineCount_ != 0)) {
      return false;
    }
    for (uint8_t i = 0; i < LedCount; ++i) {
      const Rgb output = scale(current_[i]);
      if (output.r != 0 || output.g != 0 || output.b != 0) {
        return false;
      }
    }
    return true;
  }

private:
  enum Ease : uint8_t {
    kEaseLinear = 0,
    kEaseEase = 1,
    kEaseIn = 2,
    kEaseOut = 3,
    kEaseInOut = 4,
    kEaseCosine = 5,
    kEasePulse = 6,
    kEaseNone = 7
  };

  enum RollDirection : uint8_t {
    kRollNone = 0,
    kRollRight = 1,
    kRollLeft = 2
  };

  struct Action {
    uint16_t durationMs;
    uint16_t delayMs;
    Rgb target;
    uint8_t active;
    Ease ease;
  };

  struct Line {
    Action actions[LedCount];
    uint16_t durationMs;
    Ease rollEase;
    uint8_t hasAction;
    RollDirection rollDirection;
  };

  struct LineCursor {
    const char *data;
    uint16_t length;
    uint16_t pos;
    uint8_t line;
  };

  static ParseResult ok() {
    return ParseResult{true, 0, 0, kParseOk};
  }

  static ParseResult error(uint8_t line, uint8_t column, uint8_t code) {
    return ParseResult{false, line, column, code};
  }

  ParseResult fail(ParseResult result, uint32_t nowMs) {
    lineCount_ = 0;
    currentLine_ = 0;
    repeatInfinite_ = 0;
    repeatLimit_ = 1;
    repeatRuns_ = 0;
    repeatIndex_ = 0;
    hasRepeat_ = 0;
    holding_ = 1;
    parsing_ = 0;
    brightness_ = 255;
    lineStartMs_ = nowMs;
    clearLines(lines_, MaxLines);
    for (uint8_t i = 0; i < LedCount; ++i) {
      current_[i] = Rgb{0, 0, 0};
      lineStart_[i] = current_[i];
    }
    errorBlinkActive_ = 1;
    errorBlinkStartMs_ = nowMs;
    return result;
  }

  static bool isSpace(char c) {
    return c == ' ' || c == '\t';
  }

  static bool isDigit(char c) {
    return c >= '0' && c <= '9';
  }

  static char lower(char c) {
    return c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c;
  }

  static bool isBoundary(char c) {
    return c == '\0' || c == ' ' || c == '\t' || c == ';';
  }

  static void skipSpaces(LineCursor &cursor) {
    while (cursor.pos < cursor.length && isSpace(cursor.data[cursor.pos])) {
      ++cursor.pos;
    }
  }

  static uint8_t column(const LineCursor &cursor) {
    const uint16_t oneBased = static_cast<uint16_t>(cursor.pos + 1u);
    return oneBased > 255u ? 255u : static_cast<uint8_t>(oneBased);
  }

  static bool atEndOrSegmentEnd(const LineCursor &cursor) {
    return cursor.pos >= cursor.length || cursor.data[cursor.pos] == ';';
  }

  static bool tokenEquals(const char *text, uint16_t length, const char *expected) {
    uint16_t i = 0;
    while (i < length && expected[i] != '\0') {
      if (lower(text[i]) != expected[i]) {
        return false;
      }
      ++i;
    }
    return i == length && expected[i] == '\0';
  }

  static bool startsWithWord(const LineCursor &cursor, const char *word) {
    uint16_t i = 0;
    while (word[i] != '\0') {
      if (cursor.pos + i >= cursor.length || lower(cursor.data[cursor.pos + i]) != word[i]) {
        return false;
      }
      ++i;
    }
    return cursor.pos + i >= cursor.length || isBoundary(cursor.data[cursor.pos + i]);
  }

  static uint16_t wordLength(const char *word) {
    uint16_t len = 0;
    while (word[len] != '\0') {
      ++len;
    }
    return len;
  }

  static int8_t hexValue(char c) {
    if (c >= '0' && c <= '9') {
      return static_cast<int8_t>(c - '0');
    }
    c = lower(c);
    if (c >= 'a' && c <= 'f') {
      return static_cast<int8_t>(c - 'a' + 10);
    }
    return -1;
  }

  static bool looksLikeColorAt(const LineCursor &cursor, uint16_t pos) {
    if (pos + 7u > cursor.length || cursor.data[pos] != '#') {
      return false;
    }
    for (uint8_t i = 0; i < 6; ++i) {
      if (hexValue(cursor.data[pos + 1u + i]) < 0) {
        return false;
      }
    }
    return pos + 7u == cursor.length || isBoundary(cursor.data[pos + 7u]);
  }

  static bool parseColor(LineCursor &cursor, Rgb &out) {
    if (!looksLikeColorAt(cursor, cursor.pos)) {
      return false;
    }
    const int8_t r0 = hexValue(cursor.data[cursor.pos + 1u]);
    const int8_t r1 = hexValue(cursor.data[cursor.pos + 2u]);
    const int8_t g0 = hexValue(cursor.data[cursor.pos + 3u]);
    const int8_t g1 = hexValue(cursor.data[cursor.pos + 4u]);
    const int8_t b0 = hexValue(cursor.data[cursor.pos + 5u]);
    const int8_t b1 = hexValue(cursor.data[cursor.pos + 6u]);
    out.r = static_cast<uint8_t>((r0 << 4) | r1);
    out.g = static_cast<uint8_t>((g0 << 4) | g1);
    out.b = static_cast<uint8_t>((b0 << 4) | b1);
    cursor.pos = static_cast<uint16_t>(cursor.pos + 7u);
    return true;
  }

  static bool parseUint(LineCursor &cursor, uint32_t &value) {
    if (cursor.pos >= cursor.length || !isDigit(cursor.data[cursor.pos])) {
      return false;
    }
    uint32_t parsed = 0;
    while (cursor.pos < cursor.length && isDigit(cursor.data[cursor.pos])) {
      const uint32_t digit = static_cast<uint32_t>(cursor.data[cursor.pos] - '0');
      if (parsed <= 429496729u) {
        parsed = parsed * 10u + digit;
      }
      ++cursor.pos;
    }
    value = parsed;
    return true;
  }

  static bool looksLikeIndexAt(const LineCursor &cursor, uint16_t pos) {
    if (pos >= cursor.length || !isDigit(cursor.data[pos])) {
      return false;
    }
    while (pos < cursor.length && isDigit(cursor.data[pos])) {
      ++pos;
    }
    return pos < cursor.length && cursor.data[pos] == ':';
  }

  static bool parseIndexedColor(LineCursor &cursor, uint8_t &index, Rgb &color,
                                bool &inRange) {
    uint32_t parsedIndex = 0;
    if (!parseUint(cursor, parsedIndex)) {
      return false;
    }
    if (cursor.pos >= cursor.length || cursor.data[cursor.pos] != ':') {
      return false;
    }
    ++cursor.pos;
    if (!IgnoreOutOfRange && parsedIndex >= LedCount) {
      return false;
    }
    // Indexes past the compile-time LED count are silently ignored: still
    // consume the color so the cursor advances, but the caller drops it.
    inRange = parsedIndex < LedCount;
    index = inRange ? static_cast<uint8_t>(parsedIndex) : 0;
    return parseColor(cursor, color);
  }

  static bool parseTime(LineCursor &cursor, uint16_t &milliseconds) {
    const uint16_t start = cursor.pos;
    if (cursor.pos >= cursor.length || !isDigit(cursor.data[cursor.pos])) {
      return false;
    }

    uint32_t whole = 0;
    while (cursor.pos < cursor.length && isDigit(cursor.data[cursor.pos])) {
      const uint32_t digit = static_cast<uint32_t>(cursor.data[cursor.pos] - '0');
      if (whole <= 4294967u) {
        whole = whole * 10u + digit;
      }
      ++cursor.pos;
    }

    uint16_t fracMs = 0;
    uint8_t fracDigits = 0;
    bool hasDecimal = false;
    if (cursor.pos < cursor.length && cursor.data[cursor.pos] == '.') {
      hasDecimal = true;
      ++cursor.pos;
      if (cursor.pos >= cursor.length || !isDigit(cursor.data[cursor.pos])) {
        cursor.pos = start;
        return false;
      }
      while (cursor.pos < cursor.length && isDigit(cursor.data[cursor.pos])) {
        if (fracDigits < 3) {
          fracMs = static_cast<uint16_t>(fracMs * 10u + static_cast<uint16_t>(cursor.data[cursor.pos] - '0'));
          ++fracDigits;
        }
        ++cursor.pos;
      }
      while (fracDigits < 3) {
        fracMs = static_cast<uint16_t>(fracMs * 10u);
        ++fracDigits;
      }
    }

    if (cursor.pos < cursor.length &&
        lower(cursor.data[cursor.pos]) == 'm' &&
        cursor.pos + 1u < cursor.length &&
        lower(cursor.data[cursor.pos + 1u]) == 's') {
      if (hasDecimal) {
        cursor.pos = start;
        return false;
      }
      cursor.pos = static_cast<uint16_t>(cursor.pos + 2u);
      if (cursor.pos < cursor.length && !isBoundary(cursor.data[cursor.pos])) {
        cursor.pos = start;
        return false;
      }
      if (whole > 65535u) {
        cursor.pos = start;
        return false;
      }
      milliseconds = static_cast<uint16_t>(whole);
      return true;
    }

    if (cursor.pos < cursor.length && lower(cursor.data[cursor.pos]) == 's') {
      ++cursor.pos;
      if (cursor.pos < cursor.length && !isBoundary(cursor.data[cursor.pos])) {
        cursor.pos = start;
        return false;
      }
      if (whole > 65u) {
        cursor.pos = start;
        return false;
      }
      const uint32_t totalMs = whole * 1000u + fracMs;
      if (totalMs > 65535u) {
        cursor.pos = start;
        return false;
      }
      milliseconds = static_cast<uint16_t>(totalMs);
      return true;
    }

    cursor.pos = start;
    return false;
  }

  static bool parseEase(LineCursor &cursor, Ease &ease) {
    const uint16_t start = cursor.pos;
    while (cursor.pos < cursor.length &&
           cursor.data[cursor.pos] != ';' &&
           !isSpace(cursor.data[cursor.pos])) {
      ++cursor.pos;
    }
    const uint16_t len = static_cast<uint16_t>(cursor.pos - start);
    if (len == 0) {
      return false;
    }
    const char *text = cursor.data + start;
    if (tokenEquals(text, len, "linear")) {
      ease = kEaseLinear;
      return true;
    }
    if (tokenEquals(text, len, "ease")) {
      ease = kEaseEase;
      return true;
    }
    if (tokenEquals(text, len, "ease-in")) {
      ease = kEaseIn;
      return true;
    }
    if (tokenEquals(text, len, "ease-out")) {
      ease = kEaseOut;
      return true;
    }
    if (tokenEquals(text, len, "ease-in-out")) {
      ease = kEaseInOut;
      return true;
    }
    if (tokenEquals(text, len, "cosine")) {
      ease = kEaseCosine;
      return true;
    }
    if (tokenEquals(text, len, "pulse")) {
      ease = kEasePulse;
      return true;
    }
    if (tokenEquals(text, len, "none")) {
      ease = kEaseNone;
      return true;
    }
    cursor.pos = start;
    return false;
  }

  ParseResult parsePhysicalLine(LineCursor &cursor,
                                Line (&parsedLines)[MaxLines],
                                uint8_t &parsedLineCount,
                                uint8_t &parsedRepeat,
                                uint8_t &parsedRepeatInfinite,
                                uint16_t &parsedRepeatLimit,
                                uint8_t &parsedRepeatIndex,
                                uint8_t &parsedBrightness) {
    skipSpaces(cursor);
    if (cursor.pos >= cursor.length) {
      return ok();
    }
    if (cursor.data[cursor.pos] == ';') {
      return ok();
    }
    if (cursor.data[cursor.pos] == '/' &&
        cursor.pos + 1u < cursor.length &&
        cursor.data[cursor.pos + 1u] == '/') {
      return ok();
    }
    if (cursor.data[cursor.pos] == '#' &&
        (cursor.pos + 1u >= cursor.length || isSpace(cursor.data[cursor.pos + 1u]))) {
      return ok();
    }

    if (startsWithWord(cursor, "brightness")) {
      cursor.pos = static_cast<uint16_t>(cursor.pos + wordLength("brightness"));
      skipSpaces(cursor);
      uint32_t value = 0;
      if (!parseUint(cursor, value) || value > 255u) {
        return error(cursor.line, column(cursor), kParseBadBrightness);
      }
      skipSpaces(cursor);
      if (cursor.pos != cursor.length) {
        return error(cursor.line, column(cursor), kParseTrailingInput);
      }
      parsedBrightness = static_cast<uint8_t>(value);
      return ok();
    }

    if (startsWithWord(cursor, "repeat")) {
      if (parsedRepeat) {
        return error(cursor.line, column(cursor), kParseBadRepeat);
      }
      cursor.pos = static_cast<uint16_t>(cursor.pos + wordLength("repeat"));
      skipSpaces(cursor);
      parsedRepeat = 1;
      parsedRepeatIndex = parsedLineCount;
      if (cursor.pos >= cursor.length) {
        parsedRepeatInfinite = 1;
        parsedRepeatLimit = 0;
        return ok();
      }

      uint32_t value = 0;
      if (!parseUint(cursor, value) || value == 0u || value > 65535u) {
        return error(cursor.line, column(cursor), kParseBadRepeat);
      }
      skipSpaces(cursor);
      if (cursor.pos != cursor.length) {
        return error(cursor.line, column(cursor), kParseTrailingInput);
      }
      parsedRepeatInfinite = 0;
      parsedRepeatLimit = static_cast<uint16_t>(value);
      return ok();
    }

    if (parsedLineCount >= MaxLines) {
      return error(cursor.line, column(cursor), kParseTooManyAnimationLines);
    }

    Line line;
    clearLine(line);
    ParseResult result = parseAnimationLine(cursor, line);
    if (!result.ok) {
      return result;
    }
    if (line.hasAction) {
      copyLine(parsedLines[parsedLineCount++], line);
    }
    return ok();
  }

  ParseResult parseAnimationLine(LineCursor &cursor, Line &line) {
    skipSpaces(cursor);
    if (startsWithWord(cursor, "roll-right") ||
        startsWithWord(cursor, "roll-left") ||
        startsWithWord(cursor, "roll")) {
      return parseRollLine(cursor, line);
    }

    uint8_t parsedSegmentCount = 0;
    while (cursor.pos < cursor.length) {
      skipSpaces(cursor);
      if (cursor.pos >= cursor.length) {
        break;
      }
      if (cursor.data[cursor.pos] == ';') {
        ++cursor.pos;
        continue;
      }
      ParseResult result = parseSegment(cursor, line, parsedSegmentCount);
      if (!result.ok) {
        return result;
      }
      skipSpaces(cursor);
      if (cursor.pos < cursor.length && cursor.data[cursor.pos] == ';') {
        ++cursor.pos;
      } else if (cursor.pos < cursor.length) {
        return error(cursor.line, column(cursor), kParseTrailingInput);
      }
    }

    if (!line.hasAction && parsedSegmentCount == 0) {
      return error(cursor.line, 1, kParseSyntax);
    }
    if (line.hasAction) {
      recomputeLineDuration(line);
    }
    return ok();
  }

  ParseResult parseRollLine(LineCursor &cursor, Line &line) {
    RollDirection direction = kRollRight;
    if (startsWithWord(cursor, "roll-right")) {
      cursor.pos = static_cast<uint16_t>(cursor.pos + wordLength("roll-right"));
      direction = kRollRight;
    } else if (startsWithWord(cursor, "roll-left")) {
      cursor.pos = static_cast<uint16_t>(cursor.pos + wordLength("roll-left"));
      direction = kRollLeft;
    } else if (startsWithWord(cursor, "roll")) {
      cursor.pos = static_cast<uint16_t>(cursor.pos + wordLength("roll"));
      direction = kRollRight;
    } else {
      return error(cursor.line, column(cursor), kParseSyntax);
    }

    skipSpaces(cursor);
    const uint8_t durationColumn = column(cursor);
    uint16_t durationMs = 0;
    if (!parseTime(cursor, durationMs)) {
      return error(cursor.line, durationColumn, kParseBadTime);
    }

    Ease ease = kEaseLinear;
    skipSpaces(cursor);
    if (cursor.pos < cursor.length) {
      const uint8_t easingColumn = column(cursor);
      if (!parseEase(cursor, ease)) {
        return error(cursor.line, easingColumn, kParseBadTime);
      }
      skipSpaces(cursor);
      if (cursor.pos < cursor.length) {
        return error(cursor.line, column(cursor), kParseTrailingInput);
      }
    }

    line.durationMs = durationMs;
    line.rollDirection = direction;
    line.rollEase = ease;
    line.hasAction = 1;
    return ok();
  }

  ParseResult parseSegment(LineCursor &cursor, Line &line, uint8_t &parsedSegmentCount) {
    uint8_t mask[LedCount];
    Rgb targets[LedCount];
    for (uint8_t i = 0; i < LedCount; ++i) {
      mask[i] = 0;
      targets[i] = Rgb{0, 0, 0};
    }

    uint8_t assignmentCount = 0;
    if (startsWithWord(cursor, "off")) {
      cursor.pos = static_cast<uint16_t>(cursor.pos + wordLength("off"));
      for (uint8_t i = 0; i < LedCount; ++i) {
        mask[i] = 1;
        targets[i] = Rgb{0, 0, 0};
      }
      assignmentCount = 1;
      skipSpaces(cursor);
    } else if (looksLikeIndexAt(cursor, cursor.pos)) {
      while (cursor.pos < cursor.length && looksLikeIndexAt(cursor, cursor.pos)) {
        const uint8_t indexColumn = column(cursor);
        uint8_t index = 0;
        Rgb color{0, 0, 0};
        bool inRange = false;
        if (!parseIndexedColor(cursor, index, color, inRange)) {
          return error(cursor.line, indexColumn, kParseBadIndex);
        }
        if (inRange) {
          mask[index] = 1;
          targets[index] = color;
        }
        ++assignmentCount;
        skipSpaces(cursor);
      }
    } else {
      Rgb colorList[LedCount];
      uint8_t colorCount = 0;
      uint8_t storedColorCount = 0;
      while (cursor.pos < cursor.length && cursor.data[cursor.pos] == '#') {
        if (!IgnoreOutOfRange && colorCount >= LedCount) {
          return error(cursor.line, column(cursor), kParseBadIndex);
        }
        Rgb color{0, 0, 0};
        if (!parseColor(cursor, color)) {
          return error(cursor.line, column(cursor), kParseBadColor);
        }
        if (storedColorCount < LedCount) {
          colorList[storedColorCount++] = color;
        }
        if (colorCount < 255u) {
          ++colorCount;
        }
        skipSpaces(cursor);
      }
      if (colorCount == 0) {
        return error(cursor.line, column(cursor), kParseSyntax);
      }
      if (colorCount == 1) {
        for (uint8_t i = 0; i < LedCount; ++i) {
          mask[i] = 1;
          targets[i] = colorList[0];
        }
      } else {
        for (uint8_t i = 0; i < LedCount; ++i) {
          mask[i] = 1;
          targets[i] = i < storedColorCount ? colorList[i] : Rgb{0, 0, 0};
        }
      }
      assignmentCount = colorCount;
    }

    if (assignmentCount == 0) {
      return error(cursor.line, column(cursor), kParseSyntax);
    }
    ++parsedSegmentCount;

    uint16_t durationMs = 0;
    uint16_t delayMs = 0;
    Ease ease = kEaseNone;
    skipSpaces(cursor);
    if (!atEndOrSegmentEnd(cursor)) {
      const uint8_t timingColumn = column(cursor);
      LineCursor tryTime = cursor;
      bool parsedDurationToken = false;
      if (parseTime(tryTime, durationMs)) {
        cursor = tryTime;
        ease = kEaseEase;
        parsedDurationToken = true;
      } else {
        Ease parsedEase = kEaseEase;
        if (!parseEase(cursor, parsedEase)) {
          return error(cursor.line, timingColumn, kParseBadTime);
        }
        durationMs = kDefaultDurationMs;
        ease = parsedEase;
      }
      skipSpaces(cursor);
      if (!atEndOrSegmentEnd(cursor)) {
        LineCursor tryEase = cursor;
        Ease parsedEase = kEaseEase;
        if (parsedDurationToken && parseEase(tryEase, parsedEase)) {
          cursor = tryEase;
          ease = parsedEase;
          skipSpaces(cursor);
          if (!atEndOrSegmentEnd(cursor)) {
            const uint8_t delayColumn = column(cursor);
            if (!parseTime(cursor, delayMs)) {
              return error(cursor.line, delayColumn, kParseBadTime);
            }
            skipSpaces(cursor);
          }
        } else {
          const uint8_t delayColumn = column(cursor);
          if (!parseTime(cursor, delayMs)) {
            return error(cursor.line, delayColumn, kParseBadTime);
          }
          skipSpaces(cursor);
        }
      }
      if (!atEndOrSegmentEnd(cursor)) {
        return error(cursor.line, column(cursor), kParseTrailingInput);
      }
    }

    for (uint8_t i = 0; i < LedCount; ++i) {
      if (mask[i]) {
        line.actions[i].active = 1;
        line.actions[i].target = targets[i];
        line.actions[i].durationMs = durationMs;
        line.actions[i].delayMs = delayMs;
        line.actions[i].ease = ease;
        line.hasAction = 1;
      }
    }

    return ok();
  }

  static void clearAction(Action &action) {
    action.active = 0;
    action.ease = kEaseNone;
    action.durationMs = 0;
    action.delayMs = 0;
    action.target = Rgb{0, 0, 0};
  }

  static void clearLine(Line &line) {
    line.durationMs = kFrameMs;
    line.rollEase = kEaseLinear;
    line.hasAction = 0;
    line.rollDirection = kRollNone;
    for (uint8_t i = 0; i < LedCount; ++i) {
      clearAction(line.actions[i]);
    }
  }

  static void clearLines(Line *lines, uint8_t count) {
    for (uint8_t i = 0; i < count; ++i) {
      clearLine(lines[i]);
    }
  }

  static void copyLine(Line &dst, const Line &src) {
    dst.durationMs = src.durationMs;
    dst.rollEase = src.rollEase;
    dst.hasAction = src.hasAction;
    dst.rollDirection = src.rollDirection;
    for (uint8_t i = 0; i < LedCount; ++i) {
      dst.actions[i].active = src.actions[i].active;
      dst.actions[i].ease = src.actions[i].ease;
      dst.actions[i].durationMs = src.actions[i].durationMs;
      dst.actions[i].delayMs = src.actions[i].delayMs;
      dst.actions[i].target = src.actions[i].target;
    }
  }

  static uint16_t saturatingAdd(uint16_t a, uint16_t b) {
    const uint32_t sum = static_cast<uint32_t>(a) + static_cast<uint32_t>(b);
    return sum > 65535u ? 65535u : static_cast<uint16_t>(sum);
  }

  static uint16_t clampElapsed(uint32_t elapsedMs) {
    return elapsedMs > 65535u ? 65535u : static_cast<uint16_t>(elapsedMs);
  }

  static void recomputeLineDuration(Line &line) {
    uint16_t maxDuration = 0;
    for (uint8_t i = 0; i < LedCount; ++i) {
      if (line.actions[i].active) {
        const uint16_t endMs = saturatingAdd(line.actions[i].delayMs, line.actions[i].durationMs);
        if (endMs > maxDuration) {
          maxDuration = endMs;
        }
      }
    }
    line.durationMs = maxDuration > 0u ? maxDuration : kFrameMs;
  }

  void updateTo(uint32_t nowMs) {
    if (holding_ || lineCount_ == 0) {
      return;
    }

    uint16_t guard = 0;
    while (!holding_ && lineCount_ > 0 && guard++ < 1024u) {
      const Line &line = lines_[currentLine_];
      const uint32_t elapsed = nowMs - lineStartMs_;
      if (elapsed < line.durationMs) {
        evaluateLine(line, static_cast<uint16_t>(elapsed));
        return;
      }

      evaluateLine(line, line.durationMs);
      const uint32_t nextStartMs = lineStartMs_ + line.durationMs;
      uint8_t nextLine = static_cast<uint8_t>(currentLine_ + 1u);
      if (hasRepeat_ && nextLine == repeatIndex_) {
        ++repeatRuns_;
        if (repeatInfinite_ || repeatRuns_ < repeatLimit_) {
          enterLine(0, nextStartMs);
          continue;
        }
      }

      if (nextLine < lineCount_) {
        enterLine(nextLine, nextStartMs);
        continue;
      }

      holding_ = 1;
      return;
    }

    if (!holding_ && lineCount_ > 0) {
      evaluateLine(lines_[currentLine_], clampElapsed(nowMs - lineStartMs_));
    }
  }

  void enterLine(uint8_t index, uint32_t startMs) {
    currentLine_ = index;
    lineStartMs_ = startMs;
    for (uint8_t i = 0; i < LedCount; ++i) {
      lineStart_[i] = current_[i];
    }
  }

  void evaluateLine(const Line &line, uint16_t elapsedMs) {
    if (line.rollDirection != kRollNone) {
      evaluateRollLine(line, elapsedMs);
      return;
    }

    for (uint8_t i = 0; i < LedCount; ++i) {
      if (!line.actions[i].active) {
        current_[i] = lineStart_[i];
      } else {
        current_[i] = evaluateAction(lineStart_[i], line.actions[i], elapsedMs);
      }
    }
  }

  void evaluateRollLine(const Line &line, uint16_t elapsedMs) {
    if (line.durationMs == 0u || elapsedMs >= line.durationMs) {
      for (uint8_t i = 0; i < LedCount; ++i) {
        current_[i] = lineStart_[i];
      }
      return;
    }

    const uint16_t progress = static_cast<uint16_t>((static_cast<uint32_t>(elapsedMs) * 65535u) /
                                                    line.durationMs);
    const uint16_t eased = easeProgress(line.rollEase, progress);
    const uint32_t phase = static_cast<uint32_t>(eased) * LedCount;
    const uint8_t whole = static_cast<uint8_t>(phase / 65535u);
    const uint16_t frac = static_cast<uint16_t>(phase % 65535u);

    for (uint8_t i = 0; i < LedCount; ++i) {
      const int16_t signedIndex = static_cast<int16_t>(i);
      const int16_t signedWhole = static_cast<int16_t>(whole);
      int16_t fromIndex = signedIndex - signedWhole;
      int16_t toIndex = static_cast<int16_t>(fromIndex - 1);
      if (line.rollDirection == kRollLeft) {
        fromIndex = static_cast<int16_t>(signedIndex + signedWhole);
        toIndex = static_cast<int16_t>(fromIndex + 1);
      }
      current_[i] = frac == 0u
                        ? lineStart_[wrapIndex(fromIndex)]
                        : lerp(lineStart_[wrapIndex(fromIndex)],
                               lineStart_[wrapIndex(toIndex)],
                               frac);
    }
  }

  static Rgb evaluateAction(Rgb start, const Action &action, uint16_t lineElapsedMs) {
    if (lineElapsedMs < action.delayMs) {
      return start;
    }
    const uint16_t elapsed = static_cast<uint16_t>(lineElapsedMs - action.delayMs);
    if (action.ease == kEasePulse) {
      if (action.durationMs == 0u || elapsed >= action.durationMs) {
        return start;
      }
      const uint16_t progress = static_cast<uint16_t>((static_cast<uint32_t>(elapsed) * 65535u) / action.durationMs);
      return lerp(start, action.target, pulseProgress(progress));
    }
    if (action.ease == kEaseNone || action.durationMs == 0u || elapsed >= action.durationMs) {
      return action.target;
    }

    const uint16_t progress = static_cast<uint16_t>((static_cast<uint32_t>(elapsed) * 65535u) / action.durationMs);
    const uint16_t eased = easeProgress(action.ease, progress);
    return lerp(start, action.target, eased);
  }

  static Rgb lerp(Rgb start, Rgb end, uint16_t amount) {
    Rgb out;
    out.r = lerpChannel(start.r, end.r, amount);
    out.g = lerpChannel(start.g, end.g, amount);
    out.b = lerpChannel(start.b, end.b, amount);
    return out;
  }

  static uint8_t wrapIndex(int16_t index) {
    while (index < 0) {
      index = static_cast<int16_t>(index + LedCount);
    }
    while (index >= static_cast<int16_t>(LedCount)) {
      index = static_cast<int16_t>(index - LedCount);
    }
    return static_cast<uint8_t>(index);
  }

  static uint8_t lerpChannel(uint8_t start, uint8_t end, uint16_t amount) {
    const int32_t delta = static_cast<int32_t>(end) - static_cast<int32_t>(start);
    const int32_t value = static_cast<int32_t>(start) +
                          static_cast<int32_t>((delta * static_cast<int32_t>(amount) +
                                                (delta >= 0 ? 32767 : -32767)) /
                                               65535);
    if (value <= 0) {
      return 0;
    }
    if (value >= 255) {
      return 255;
    }
    return static_cast<uint8_t>(value);
  }

  static uint16_t easeProgress(Ease ease, uint16_t progress) {
    switch (ease) {
    case kEaseLinear:
      return progress;
    case kEaseEase:
      return cubicBezier(progress, 16384u, 6554u, 16384u, 65535u);
    case kEaseIn:
      return cubicBezier(progress, 27525u, 0u, 65535u, 65535u);
    case kEaseOut:
      return cubicBezier(progress, 0u, 0u, 38010u, 65535u);
    case kEaseInOut:
      return cubicBezier(progress, 27525u, 0u, 38010u, 65535u);
    case kEaseCosine:
      return cosineEase(progress);
    case kEasePulse:
      return pulseProgress(progress);
    case kEaseNone:
    default:
      return progress;
    }
  }

  static uint16_t mulQ16(uint16_t a, uint16_t b) {
    return static_cast<uint16_t>((static_cast<uint32_t>(a) * static_cast<uint32_t>(b) + 32767u) / 65535u);
  }

  static uint16_t bezierCoord(uint16_t t, uint16_t p1, uint16_t p2) {
    const uint16_t oneMinusT = static_cast<uint16_t>(65535u - t);
    const uint16_t omt2 = mulQ16(oneMinusT, oneMinusT);
    const uint16_t t2 = mulQ16(t, t);
    const uint16_t t3 = mulQ16(t2, t);
    const uint16_t a = mulQ16(mulQ16(omt2, t), p1);
    const uint16_t b = mulQ16(mulQ16(oneMinusT, t2), p2);
    uint32_t result = static_cast<uint32_t>(a) * 3u + static_cast<uint32_t>(b) * 3u + t3;
    if (result > 65535u) {
      result = 65535u;
    }
    return static_cast<uint16_t>(result);
  }

  static uint16_t cubicBezier(uint16_t progress, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2) {
    uint16_t lo = 0;
    uint16_t hi = 65535u;
    for (uint8_t i = 0; i < 14; ++i) {
      const uint16_t mid = static_cast<uint16_t>((static_cast<uint32_t>(lo) + hi) / 2u);
      const uint16_t x = bezierCoord(mid, x1, x2);
      if (x < progress) {
        lo = static_cast<uint16_t>(mid + 1u);
      } else {
        hi = mid;
      }
    }
    const uint16_t t = static_cast<uint16_t>((static_cast<uint32_t>(lo) + hi) / 2u);
    return bezierCoord(t, y1, y2);
  }

  static uint16_t cosineEase(uint16_t progress) {
    static constexpr uint16_t table[17] = {
      0u, 630u, 2494u, 5522u, 9597u, 14563u, 20228u, 26375u, 32767u,
      39160u, 45307u, 50972u, 55938u, 60013u, 63041u, 64905u, 65535u
    };
    const uint8_t index = static_cast<uint8_t>(progress >> 12);
    if (index >= 16u) {
      return 65535u;
    }
    const uint16_t frac = static_cast<uint16_t>(progress & 0x0fffu);
    const uint16_t a = table[index];
    const uint16_t b = table[index + 1u];
    const uint32_t mixed = static_cast<uint32_t>(a) * (4096u - frac) + static_cast<uint32_t>(b) * frac;
    return static_cast<uint16_t>((mixed + 2048u) >> 12);
  }

  static uint16_t pulseProgress(uint16_t progress) {
    if (progress <= 32767u) {
      return cosineEase(static_cast<uint16_t>(static_cast<uint32_t>(progress) * 2u));
    }
    const uint32_t falling = (65535u - static_cast<uint32_t>(progress)) * 2u;
    return cosineEase(static_cast<uint16_t>(falling > 65535u ? 65535u : falling));
  }

  Rgb scale(Rgb color) const {
    Rgb out;
    out.r = scaleChannel(color.r);
    out.g = scaleChannel(color.g);
    out.b = scaleChannel(color.b);
    return out;
  }

  uint8_t scaleChannel(uint8_t value) const {
    return static_cast<uint8_t>((static_cast<uint16_t>(value) * brightness_ + 127u) / 255u);
  }

  Line lines_[MaxLines];
  Rgb current_[LedCount];
  Rgb lineStart_[LedCount];
  uint32_t lineStartMs_;
  uint16_t repeatLimit_;
  uint16_t repeatRuns_;
  uint8_t lineCount_;
  uint8_t currentLine_;
  uint8_t repeatIndex_;
  uint8_t hasRepeat_;
  uint8_t repeatInfinite_;
  uint8_t errorBlinkActive_;
  volatile uint8_t parsing_;
  uint8_t holding_;
  uint8_t brightness_;
  uint32_t errorBlinkStartMs_;
};

} // namespace sdled
