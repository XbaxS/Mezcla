#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${MEZCLA_BUILD_DIR:-${TMPDIR:-/tmp}/mezcla-build}"
app_dir="$project_dir/../Mezcla.app"
staged_app="$build_dir/Mezcla.app"
mkdir -p "$build_dir" "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
swift_flags=(-sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx14.4 -swift-version 5 -module-cache-path "$build_dir/swift-cache")
xcrun clang -O2 -fobjc-arc -mmacosx-version-min=14.4 -c "$project_dir/Sources/AudioBridge.m" -o "$build_dir/AudioBridge.o"
xcrun swiftc "${swift_flags[@]}" -O -import-objc-header "$project_dir/Sources/AudioBridge.h" "$project_dir"/Sources/*.swift "$build_dir/AudioBridge.o" -framework AppKit -framework SwiftUI -framework CoreAudio -framework Foundation -o "$staged_app/Contents/MacOS/Mezcla"
cp "$project_dir/Info.plist" "$staged_app/Contents/Info.plist"
if [[ -f "$project_dir/Assets/AppIcon.icns" ]]; then cp "$project_dir/Assets/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"; fi
# Sign in temporary storage, where synced-folder metadata cannot invalidate signing.
xattr -cr "$staged_app"
codesign --force --sign - --identifier cl.mezcla.audio "$staged_app"
codesign --verify --strict "$staged_app"
ditto --norsrc --noextattr "$staged_app" "$app_dir"
xattr -cr "$app_dir"
echo "Aplicación creada: $app_dir"
