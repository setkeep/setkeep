#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
watch_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/setkeep-watch-tests.XXXXXX")
trap 'rm -rf "$watch_test_dir"' EXIT HUP INT TERM
xcrun swiftc -module-cache-path "$watch_test_dir/ModuleCache" \
  "$repo_dir/ios/WatchShared/RestWatchProtocol.swift" \
  "$repo_dir/tool/apple_watch/RestWatchProtocolTests.swift" \
  -o "$watch_test_dir/rest-watch-tests"
"$watch_test_dir/rest-watch-tests"
