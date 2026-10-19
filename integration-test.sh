#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${MEZCLA_BUILD_DIR:-${TMPDIR:-/tmp}/mezcla-build}"
mkdir -p "$build_dir"
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
xcrun clang -fobjc-arc -O2 -mmacosx-version-min=14.4 "$project_dir/Tests/Integration.m" "$project_dir/Sources/AudioBridge.m" -framework Foundation -framework CoreAudio -o "$build_dir/mezcla-integration"
"$build_dir/mezcla-integration"
