# AquaLangMacOS

A new macOS-native codebase for AquaLang behavior:

- keeps recent typed keys in an in-memory buffer,
- detects a configurable double-modifier trigger (default: Shift),
- backspaces the buffered text,
- switches to the next enabled keyboard input source,
- replays the buffered key strokes in the new language.

> Notes:
> - This is designed for bilingual workflow (e.g., English/Hebrew).
> - No keystroke log file is written; the buffer is memory-only and is cleared after replacement.

## Tech stack

- Swift 5.9+
- Quartz / CoreGraphics event taps (`CGEventTap`)
- Carbon Text Input Source APIs (`TIS*`) for input source switching

## Project layout

- `Sources/AquaLangCore`: shared core logic (buffer + configurable trigger detection)
- `Sources/AquaLangMac`: macOS runtime (event tap, replay engine, input source switching)
- `Tests/AquaLangCoreTests`: unit tests for core behavior

## Build

```bash
cd aqualang-macos
swift build -c release
```

## Run

```bash
cd aqualang-macos
swift run AquaLangMac
```

Optional trigger override via environment variable:

```bash
AQUALANG_TRIGGER=control
swift run AquaLangMac
```

Supported trigger values: `shift` (default), `control`/`ctrl`, `option`/`alt`, `command`/`cmd`.

At first run, macOS should prompt for Accessibility permission.
If needed, manually enable it:

- **System Settings → Privacy & Security → Accessibility**
- (Depending on macOS version/policy) **Input Monitoring** may also be required.

## Behavior details

- Trigger: double-tap configured modifier key (default: **Shift**) within ~420ms.
- Buffered text max length: 220 non-modifier key events.
- Replacement flow:
  1. Count printable text length after local backspace compensation.
  2. Emit that many backspaces.
  3. Switch to next select-capable keyboard input source.
  4. Replay buffered key events.

## Limitations / TODO

- Current source-switch strategy cycles to the next enabled source.
  - You can extend this to explicit source pairs (e.g., only EN↔HE).
- Some applications with custom event handling may behave differently.
- Hardened Runtime / notarization / launch-agent packaging are not included yet.

## Development

Run tests:

```bash
cd AquaLangMacOS
swift test
```

