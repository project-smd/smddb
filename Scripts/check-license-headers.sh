#!/usr/bin/env bash
#
# Verify every tracked Markdown file carries the SPDX licence header.
#
# Headers are checked rather than merely applied once because the failure is silent: this
# repository has no build to break, so a document written without one is wrong in a way nothing
# else in the toolchain would ever mention. Checking `git ls-files` rather than a directory walk
# keeps the scope exactly "what is in the repository".
#
# Markdown rather than source because that is what is here. Adding a language means adding its
# comment syntax to the case below and its glob to the list at the bottom; the rest is unchanged.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

project="smddb"

spdx='<!-- SPDX-License-Identifier: Apache-2.0 -->'
copyright="<!-- Copyright (c) [0-9]\{4\} the ${project} project authors -->"

fail=0
while IFS= read -r file; do
    # The header is the top of the file. A little slack, so a document may carry an editor
    # directive or a blank line above it, but not so much that it can drift into the prose.
    if ! head -3 "$file" | grep -qxF "$spdx"; then
        echo "missing SPDX identifier: $file"
        fail=1
        continue
    fi
    if ! head -4 "$file" | grep -q "$copyright"; then
        echo "missing copyright line: $file"
        fail=1
    fi
done < <(git ls-files '*.md')

if [ "$fail" -ne 0 ]; then
    cat <<USAGE

Add to the top of each file listed above, before the title:

    $spdx
    <!-- Copyright (c) $(date +%Y) the ${project} project authors -->

They are HTML comments, so GitHub and every other Markdown renderer leave them out of the page.

USAGE
    exit 1
fi

echo "licence headers OK ($(git ls-files '*.md' | wc -l | tr -d ' ') files)"
