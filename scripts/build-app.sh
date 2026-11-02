#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
configuration="${1:-release}"
sdk_options=()
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  sdk_options=(--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk)
fi
swift build --build-system native "${sdk_options[@]}" -c "$configuration"
binary_dir="$(swift build --build-system native "${sdk_options[@]}" -c "$configuration" --show-bin-path)"
app="$PWD/dist/Cadence.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Cadence" "$app/Contents/MacOS/Cadence"
cp "$binary_dir/CadenceRunner" "$app/Contents/MacOS/CadenceRunner"
cp scripts/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources"
codesign --force --deep --sign - "$app"
print "$app"
