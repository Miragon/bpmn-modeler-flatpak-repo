#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly POLICY="$REPO_ROOT/scripts/check-publication-policy.sh"
readonly KEY_A="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
readonly KEY_B="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

release_json() {
    local file="$1"
    local tag="$2"
    local digest="$3"
    local release_id="$4"
    local published_at="$5"
    local revision="$6"
    local signing_key_fingerprint="${7:-$KEY_A}"

    jq -n \
        --arg tag "$tag" \
        --arg digest "$digest" \
        --argjson release_id "$release_id" \
        --arg published_at "$published_at" \
        --arg revision "$revision" \
        --arg signing_key_fingerprint "$signing_key_fingerprint" \
        '{
          tag: $tag,
          asset_digest: $digest,
          release_id: $release_id,
          published_at: $published_at,
          publisher_revision: $revision,
          repository_url: "https://example.test/repo/",
          signing_key_fingerprint: $signing_key_fingerprint
        }' > "$file"
}

policy() {
    local candidate="$1"
    local current="$2"
    local revision="$3"
    local repository_url="$4"
    local allow_override="${5:-false}"
    "$POLICY" "$candidate" "$current" "$revision" "$repository_url" \
        "$KEY_A" "$allow_override"
}

current="$work_dir/current.json"
candidate="$work_dir/candidate.json"
release_json "$current" "vscode-v1.6.0" "sha256:aaaa" 106 \
    "2026-08-06T12:00:00Z" "1"

release_json "$candidate" "vscode-v1.6.0" "sha256:aaaa" 106 \
    "2026-08-06T12:00:00Z" "1"
[[ "$(policy "$candidate" "$current" 1 "https://example.test/repo/")" == "skip" ]]
[[ "$(policy "$candidate" "$current" 2 "https://example.test/repo/")" == "publish" ]]
[[ "$(policy "$candidate" "$current" 1 "https://new.example.test/repo/")" == "publish" ]]

release_json "$candidate" "vscode-v1.6.0" "sha256:bbbb" 106 \
    "2026-08-06T12:00:00Z" "1"
if policy "$candidate" "$current" 1 "https://example.test/repo/" >/dev/null 2>&1; then
    echo "Publication policy accepted a replaced asset." >&2
    exit 1
fi

release_json "$candidate" "vscode-v1.6.0" "sha256:aaaa" 999 \
    "2026-08-08T12:00:00Z" "1"
if policy "$candidate" "$current" 1 "https://example.test/repo/" >/dev/null 2>&1; then
    echo "Publication policy accepted a recreated release." >&2
    exit 1
fi

release_json "$candidate" "vscode-v1.5.0" "sha256:cccc" 999 \
    "2026-08-08T12:00:00Z" "1"
if policy "$candidate" "$current" 1 "https://example.test/repo/" >/dev/null 2>&1; then
    echo "Publication policy accepted an automatic rollback." >&2
    exit 1
fi
[[ "$(policy "$candidate" "$current" 1 "https://example.test/repo/" true)" == "publish" ]]

release_json "$candidate" "vscode-v1.7.0" "sha256:dddd" 100 \
    "2026-08-01T12:00:00Z" "1"
[[ "$(policy "$candidate" "$current" 1 "https://example.test/repo/")" == "publish" ]]

release_json "$current" "vscode-v1.6.0" "sha256:aaaa" 106 \
    "2026-08-06T12:00:00Z" "1" "$KEY_B"
if policy "$candidate" "$current" 1 "https://example.test/repo/" true >/dev/null 2>&1; then
    echo "Publication policy accepted a signing-key replacement." >&2
    exit 1
fi

echo "Publication policy tests passed."
