#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly REVISION="$REPO_ROOT/scripts/publisher-revision.sh"
readonly KEY_A="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
readonly KEY_B="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"

upper_revision="$("$REVISION" "$KEY_A")"
lower_revision="$("$REVISION" "${KEY_A,,}")"
other_revision="$("$REVISION" "$KEY_B")"

[[ "$upper_revision" =~ ^[0-9a-f]{64}$ ]]
[[ "$upper_revision" == "$lower_revision" ]]
[[ "$upper_revision" != "$other_revision" ]]

if "$REVISION" invalid >/dev/null 2>&1; then
    echo "Publisher revision accepted an invalid fingerprint." >&2
    exit 1
fi

echo "Publisher revision tests passed."
