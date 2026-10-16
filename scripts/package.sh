#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
architecture="${1:-$(uname -m)}"
"$project_root/scripts/build.sh" Release "$architecture"
mkdir -p "$project_root/deploy"
app_path="$project_root/.build/xcode/Build/Products/Release/Mindora.app"
archive_path="$project_root/deploy/Mindora-$architecture.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
printf '%s\n' "$archive_path"
