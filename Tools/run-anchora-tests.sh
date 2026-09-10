#!/bin/sh
# Behavioural tests for Anchora's Swift core.  These files carry no AppKit or
# Skim dependency, so they compile and run without building the app.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -O -parse-as-library \
    "$root/Anchora/AnchoraPaperMap.swift" \
    "$root/Anchora/AnchoraMarkdown.swift" \
    "$root/Anchora/AnchoraTextQuality.swift" \
    "$root/Anchora/AnchoraTurn.swift" \
    "$root/Anchora/AnchoraCapture.swift" \
    "$root/Anchora/AnchoraPrompts.swift" \
    "$root/Anchora/AnchoraSettings.swift" \
    "$root/Anchora/AnchoraChatModel.swift" \
    "$root/Tools/AnchoraCoreTests.swift" \
    -o "$out/anchora-core-tests"
"$out/anchora-core-tests"
