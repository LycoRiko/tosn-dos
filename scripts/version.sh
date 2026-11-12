#!/bin/sh
# "1.0-<short commit>" while the project is pre-release.
#
# There are no releases to number yet, so the commit is the only identifier worth
# carrying: a test build can always be traced back to the tree it came from.
# Pass the result as MARKETING_VERSION when building.
hash=$(git -C "$(dirname "$0")/.." rev-parse --short HEAD 2>/dev/null || true)
[ -n "$hash" ] || hash="nogit"
printf '1.0-%s\n' "$hash"
