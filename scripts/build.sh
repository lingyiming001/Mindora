#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
configuration="${1:-Debug}"
architecture="${2:-$(uname -m)}"
case "$configuration" in Debug|Release) ;; *) echo "Usage: build.sh [Debug|Release] [arm64|x86_64|universal]" >&2; exit 2 ;; esac
case "$architecture" in arm64|x86_64) architectures="$architecture" ;; universal) architectures="arm64 x86_64" ;; *) echo "Unsupported architecture" >&2; exit 2 ;; esac
mkdir -p .build
xcodebuild -quiet -project Mindora.xcodeproj -scheme Mindora -configuration "$configuration" -destination 'generic/platform=macOS' -derivedDataPath .build/xcode ARCHS="$architectures" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' build
app_path=".build/xcode/Build/Products/$configuration/Mindora.app"
codesign --force --sign - "$app_path"
printf '%s\n' "$project_root/$app_path"
