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

## Copyright (C) 2026 Eliyahu Mashiah.

This project is dual-licensed:

1. For individuals, GNU Affero General Public License v3.0 (AGPLv3)
   You may use, modify, and distribute this software under the terms of the AGPLv3.
   See the LICENSE file for details.

2. Commercial License
   Organizations that cannot comply with the AGPLv3 (for example,
   those distributing proprietary derivative works or offering
   the software as part of a closed-source SaaS product) must
   obtain a commercial license from Eliyahu Mashiah.

For commercial licensing inquiries, please contact: aqualang.soft@gmail.com

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
./aqualang start
./aqualang status
./aqualang stop
```

The script starts AquaLang in the background and stores logs in:
- `~/.local/state/aqualang/aqualang.log`

If no packaged binary is found, it uses `.build/release/AquaLangMac` from a local release build.

## Package for end users (no `swift run`)

```bash
cd aqualang-macos
./scripts/package-release.sh
```

This creates:
- `release/bin/AquaLangMac` (prebuilt executable)

Distribute both:
- `aqualang`
- `release/`

Then end users can run only:

```bash
./aqualang start
./aqualang stop
./aqualang status
```

Optional trigger override via environment variable:

```bash/zsh
export AQUALANG_TRIGGER=control
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
  3. Buffer is cleared when Enter, Tab, or mouse click is detected (field-boundary safety).
  4. Switch to next select-capable keyboard input source.
  5. Replay buffered key events.

## Limitations / TODO

- Current source-switch strategy cycles to the next enabled source.
  - You can extend this to explicit source pairs (e.g., only EN↔HE).
- Some applications with custom event handling may behave differently.
- Hardened Runtime / notarization / launch-agent packaging are not included yet.

## Development

Run tests:

```bash
cd aqualang-macos
swift test
```

