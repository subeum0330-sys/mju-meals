#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

# Keep generated signed bundles outside folders synchronized by a file provider.
build_dir="${TMPDIR:-/tmp}/mjubap-validation-build"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
sdk_options=()
plugin_options=()
if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" &&
      -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    # This CLT's 27.0 SDK refers to a SwiftUI macro plugin only shipped in Xcode.
    sdk_options=(--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk)
fi
testing_plugins=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" &&
      -f "$testing_plugins/libTestingMacros.dylib" ]]; then
    # CLT keeps Swift Testing's macro plugin outside the default plugin path.
    plugin_options=(-Xswiftc -plugin-path -Xswiftc "$testing_plugins")
fi
swift test --disable-xctest --disable-sandbox \
    --cache-path "$project_dir/.build/Cache" --scratch-path "$build_dir" \
    "${sdk_options[@]}" "${plugin_options[@]}" "$@"
