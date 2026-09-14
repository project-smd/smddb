#!/usr/bin/env bash
#
# Verify every tracked Markdown and Swift file carries the SPDX licence header.
#
# Headers are checked rather than merely applied once because the failure is silent: nothing else in
# the toolchain looks, so a file written without one is wrong in a way nothing would ever mention.
# Checking `git ls-files` rather than a directory walk keeps the scope exactly "what is in the
# repository" — build products under .build carry other people's headers and must not be examined.
#
# Adding a language means adding its comment syntax to the case below and its glob to the list at
# the bottom; the rest is unchanged.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

project="smddb"

fail=0
while IFS= read -r file; do
    case "$file" in
        *.md)
            spdx='<!-- SPDX-License-Identifier: Apache-2.0 -->'
            copyright="<!-- Copyright (c) [0-9]\{4\} the ${project} project authors -->"
            # The header is the top of the file. A little slack, so a document may carry an editor
            # directive or a blank line above it, but not so much that it can drift into the prose.
            spdx_within=3
            copyright_within=4
            ;;
        *.swift)
            spdx='// SPDX-License-Identifier: Apache-2.0'
            copyright="// Copyright (c) [0-9]\{4\} the ${project} project authors"
            # The SPDX line is first, except in a manifest, where `// swift-tools-version:` must stay
            # on line 1 or SwiftPM cannot read the package at all.
            spdx_within=5
            copyright_within=12
            ;;
        *)
            continue
            ;;
    esac
    if ! head -"$spdx_within" "$file" | grep -qxF "$spdx"; then
        echo "missing SPDX identifier: $file"
        fail=1
        continue
    fi
    if ! head -"$copyright_within" "$file" | grep -q "$copyright"; then
        echo "missing copyright line: $file"
        fail=1
    fi
done < <(git ls-files '*.md' '*.swift')

if [ "$fail" -ne 0 ]; then
    cat <<USAGE

Add to the top of each file listed above, before the title — in Markdown as HTML comments, which
every renderer leaves out of the page; in Swift as line comments, after any \`// swift-tools-version:\`
line, which must stay first:

    <!-- SPDX-License-Identifier: Apache-2.0 -->
    <!-- Copyright (c) $(date +%Y) the ${project} project authors -->

    // SPDX-License-Identifier: Apache-2.0
    // Copyright (c) $(date +%Y) the ${project} project authors

USAGE
    exit 1
fi

echo "licence headers OK ($(git ls-files '*.md' '*.swift' | wc -l | tr -d ' ') files)"
