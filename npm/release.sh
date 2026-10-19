#!/bin/sh
# Builds the release binary into the npm package. Run from the repo root, then `cd npm && npm publish`.
set -e
swift build -c release
cp .build/release/earshot npm/bin/earshot
chmod +x npm/bin/earshot
cp README.md LICENSE npm/
