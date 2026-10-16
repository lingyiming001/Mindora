#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
mkdir -p .build/AppIcon.iconset
# Extract the square icon area from the supplied 2172 × 724 brand image.
sips -c 512 512 --cropOffset 100 220 Logo.png --out .build/Logo-square.png >/dev/null
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" .build/Logo-square.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    pixels=$((size * 2))
    sips -z "$pixels" "$pixels" .build/Logo-square.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 scripts/make_icns.py
