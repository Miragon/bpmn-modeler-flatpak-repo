#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

if [[ $# -ne 1 || ! "$1" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    echo "Usage: $0 <signing-key-fingerprint>" >&2
    exit 2
fi
readonly SIGNING_KEY_FINGERPRINT="${1^^}"

files=(
    .github/workflows/publish-flatpak.yml
    scripts/check-publication-policy.sh
    scripts/publish-release.sh
    scripts/publisher-revision.sh
    scripts/read_flatpak_metadata.py
    scripts/resolve-release.sh
    scripts/select-release.jq
)

manifest_revision="$(
    (
    cd "$REPO_ROOT"
    sha256sum "${files[@]}"
    ) | sha256sum | awk '{ print $1 }'
)"

printf '%s\n%s\n' "$manifest_revision" "$SIGNING_KEY_FINGERPRINT" \
    | sha256sum \
    | awk '{ print $1 }'
