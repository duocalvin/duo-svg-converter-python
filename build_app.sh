#!/usr/bin/env bash
set -euo pipefail

# Build a macOS .app bundle using PyInstaller.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v pyinstaller >/dev/null 2>&1; then
  echo "PyInstaller not found. Install dependencies first:"
  echo "  pip install -r requirements.txt"
  exit 1
fi

APP_NAME="Duo SVG Converter"

rm -rf build dist "${APP_NAME}.spec" || true

pyinstaller \
  --noconfirm \
  --clean \
  --windowed \
  --name "${APP_NAME}" \
  --add-data "convert_to_SVG.sh:." \
  gui.py

echo "\nBuilt app at: dist/${APP_NAME}.app"

