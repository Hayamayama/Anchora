#!/bin/sh
#
# Build, sign, and package Anchora for release.
#
#   Tools/package-release.sh
#
# With no environment set this produces the ad-hoc signed build we ship today.
# Anyone who downloads that from a browser gets it quarantined, and macOS 15
# and later no longer accept Control-click -> Open as a way past that, so it
# needs either the install command in README.md or a trip through System
# Settings.
#
# Set both of these and the same command produces a notarised build that opens
# with no warning at all:
#
#   ANCHORA_SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   ANCHORA_NOTARY_PROFILE  a keychain profile made with
#                           xcrun notarytool store-credentials
#
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

# Info.plist in the source still has $(CURRENT_PROJECT_VERSION) unexpanded,
# so the build number is read back from the built bundle instead.
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
app="Distribution/Anchora.app"
zip="Distribution/Anchora-${version}-macos-arm64.zip"
derived=/private/tmp/anchora-release-derived

say() { printf '\n== %s\n' "$1"; }

say "Checks"
Tools/run-anchora-tests.sh
Tools/find-orphaned-methods.py SKRightSideViewController.m

say "Build (Release)"
xcodebuild -project Skim.xcodeproj -scheme Skim -configuration Release \
    -derivedDataPath "$derived" \
    build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- > /private/tmp/anchora-package.log 2>&1 \
    || { echo "build failed; see /private/tmp/anchora-package.log"; exit 1; }
errors=$(grep -cE '^/.*: error: ' /private/tmp/anchora-package.log || true)
[ "$errors" = "0" ] || { echo "$errors compile error(s); see /private/tmp/anchora-package.log"; exit 1; }

say "Stage"
mkdir -p Distribution
rm -rf "$app" "$zip"
cp -R "$derived/Build/Products/Release/Anchora.app" "$app"
# Extended attributes from the build tree confuse codesign and travel into the
# archive for no reason.
xattr -cr "$app"

if [ -n "$ANCHORA_SIGN_IDENTITY" ]; then
    identity="$ANCHORA_SIGN_IDENTITY"
    # Notarisation requires the hardened runtime and a secure timestamp.
    extra="--options runtime --timestamp"
    say "Sign as $identity"
else
    identity="-"
    extra=""
    say "Sign ad-hoc (set ANCHORA_SIGN_IDENTITY for a distributable build)"
fi

# Notarization inspects every embedded Mach-O independently, not only the
# four bundle types below happen to nest as their own directories. Sparkle's
# Autoupdate sits as a bare binary beside its framework's own dylib rather
# than wrapped in a bundle of its own, and Skim ships two command-line tools
# (skimpdf, skimnotes) the same way -- signing the directory that contains
# them never reaches in and re-signs a loose file sitting inside it. Left
# alone, all three kept whatever ad-hoc signature Xcode's own build gave
# them: no Developer ID, no secure timestamp, and for the two command-line
# tools, the debug-only get-task-allow entitlement Xcode attaches to an
# ad-hoc build -- which is exactly what the notary service rejected the
# first time this ran. Signing every Mach-O found, unconditionally and with
# no entitlements of its own, before anything else, is what actually reaches
# all of it; a bundle's own main executable gets its final signature anyway
# the moment the bundle itself is signed next.
find "$app" -type f -perm -u+x | while read -r candidate; do
    file "$candidate" | grep -q "Mach-O" || continue
    codesign --force $extra --sign "$identity" "$candidate"
done

# Inside out: nested code must already be signed when its container is.
# .plugin and .qlgenerator are bundle types too (SkimTransitions, the Quick
# Look generator) and were missing from this list, which is why signing
# their *contents* above still left the bundle-level signature stale.
find "$app" -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.mdimporter' -o -name '*.plugin' -o -name '*.qlgenerator' \) \
    -not -path "$app" \
    | awk '{ print gsub("/","/"), $0 }' | sort -rn | cut -d' ' -f2- \
    | while read -r nested; do
        codesign --force $extra --sign "$identity" "$nested"
    done
# The main app is the one piece that needs its own entitlements. Everything
# nested here is unsandboxed and needs none -- confirmed by Sparkle's own
# Updater.app carrying an empty entitlements set even from Xcode's build --
# but the app itself has to tell the hardened runtime to tolerate the
# non-Apple-signed libraries bundled inside it
# (com.apple.security.cs.disable-library-validation), or it refuses to
# launch wherever that runtime enforces its defaults: a failure notarization
# itself would not catch, since it checks signatures, not whether the app
# can actually start.
codesign --force $extra --entitlements Skim.entitlements --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

say "Package"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

if [ -n "$ANCHORA_NOTARY_PROFILE" ]; then
    say "Notarise"
    xcrun notarytool submit "$zip" --keychain-profile "$ANCHORA_NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    # The archive has to be rebuilt so it carries the stapled ticket.
    rm -f "$zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
    say "Gatekeeper"
    spctl -a -vv "$app"
else
    say "Not notarised (set ANCHORA_NOTARY_PROFILE to notarise)"
fi

say "Result"
echo "version : $version ($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist"))"
echo "app     : $app"
echo "archive : $zip  ($(du -h "$zip" | cut -f1))"
echo "sha-256 : $(shasum -a 256 "$zip" | cut -d' ' -f1)"
