#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
sdk_options=()
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  sdk_options=(--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk)
fi
swift build --build-system native "${sdk_options[@]}"
binary_dir="$(swift build --build-system native "${sdk_options[@]}" --show-bin-path)"
CADENCE_TEST_RUNNER="$binary_dir/CadenceRunner" "$binary_dir/CadenceChecks" "$@"
