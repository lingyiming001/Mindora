#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-Release}"
"$project_root/scripts/build.sh" "$configuration"
open "$project_root/.build/xcode/Build/Products/$configuration/Mindora.app"
