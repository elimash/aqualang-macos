#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/release"
BIN_DIR="$OUTPUT_DIR/bin"

cd "$ROOT_DIR"

swift build -c release

mkdir -p "$BIN_DIR"
cp "$ROOT_DIR/.build/release/AquaLangMac" "$BIN_DIR/AquaLangMac"
chmod +x "$BIN_DIR/AquaLangMac"
chmod +x "$ROOT_DIR/aqualang"

echo "Release package prepared in: $OUTPUT_DIR"
echo "Distribute the 'release/' folder together with the 'aqualang' script."
