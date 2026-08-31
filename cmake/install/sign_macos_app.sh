#!/bin/bash
set -e

IDENTITY="$1"
APP="$2"
ENTITLEMENTS="$3"
EXE="$4"

# No hardened runtime (--options runtime,library): library validation requires all
# mapped libraries to carry the SAME Team ID as the process, and a self-signed
# identity has none — dyld then aborts at launch ("mapping process and mapped file
# (non-platform) have different Team IDs", seen fleet-wide on build .70/.73,
# 2026-08-31). Hardened runtime is only needed for notarized Developer ID builds;
# re-add the options (or the com.apple.security.cs.disable-library-validation
# entitlement) if this fork ever moves to a Developer ID certificate.
SIGN=(codesign --force --timestamp -s "$IDENTITY")

find "$APP" \( -name "*.dylib" -o -name "*.so" \) -exec "${SIGN[@]}" {} \;
find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -exec "${SIGN[@]}" {} \;

for f in "$APP/Contents/MacOS/"*; do
	if [ -f "$f" ]; then
		"${SIGN[@]}" "$f"
	fi
done

"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP/Contents/MacOS/$EXE"
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
