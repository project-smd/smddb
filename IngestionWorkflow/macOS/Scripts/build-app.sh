#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 the smddb project authors
#
# Build Ingest and wrap it as an app bundle, printing the bundle's path on stdout.
#
#     open "$(Scripts/build-app.sh)"
#     open "$(Scripts/build-app.sh -c release)" --args --stage assign
#
# A bundle is needed because VLCKit is a dynamic framework. SwiftPM links the executable against it
# but leaves it where it was unpacked, under .build/artifacts, and points the executable's rpath at
# a PackageFrameworks folder it never fills — so the bare executable, and the test bundle, cannot be
# loaded. The bundle carries the framework in Contents/Frameworks, where an app looks for its own.
#
# On the way, the framework is linked into that PackageFrameworks folder too, which is what makes
# `swift test` and `swift run Ingest` work once this has been run for the configuration in question.
#
# The signature is ad hoc: enough to run here, not to distribute. Anything else in the build is
# SwiftPM's own; the bundle is assembled from its products and rebuilt from scratch every time.
set -euo pipefail

configuration=debug
while [ $# -gt 0 ]; do
    case "$1" in
        -c|--configuration)
            configuration="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '5,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

cd "$(dirname "$0")/.."

# Everything swift build says goes to stderr, so the only thing on stdout is the bundle's path.
swift build -c "$configuration" 1>&2
products="$(swift build -c "$configuration" --show-bin-path)"

frameworks=(.build/artifacts/*/VLCKit/VLCKit.xcframework/macos-*/VLCKit.framework)
if [ "${#frameworks[@]}" -ne 1 ] || [ ! -d "${frameworks[0]}" ]; then
    echo "expected exactly one macOS VLCKit.framework under .build/artifacts, found: ${frameworks[*]}" >&2
    exit 1
fi
framework="$PWD/${frameworks[0]}"

mkdir -p "$products/PackageFrameworks"
ln -sfn "$framework" "$products/PackageFrameworks/VLCKit.framework"

app="$products/Ingest.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$products/Ingest" "$app/Contents/MacOS/Ingest"
cp Bundle/Info.plist "$app/Contents/Info.plist"
cp -R "$framework" "$app/Contents/Frameworks/"

# The linker's rpaths point into .build; add the one an app bundle uses. install_name_tool warns
# that this breaks the linker's ad hoc signature, which the signing below replaces.
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Ingest" 2>&1 \
    | grep -v "invalidate the code signature" 1>&2 || true
codesign --force --sign - "$app/Contents/Frameworks/VLCKit.framework" 1>&2
codesign --force --sign - "$app" 1>&2

echo "$app"
