#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "Usage: $0 <candidate-release.json> <current-release.json> <publisher-revision> <repository-url> <signing-key-fingerprint> <allow-override>" >&2
    exit 2
fi

readonly CANDIDATE_RELEASE="$1"
readonly CURRENT_RELEASE="$2"
readonly PUBLISHER_REVISION="$3"
readonly REPOSITORY_URL="$4"
readonly SIGNING_KEY_FINGERPRINT="${5^^}"
readonly ALLOW_OVERRIDE="$6"

for file in "$CANDIDATE_RELEASE" "$CURRENT_RELEASE"; do
    [[ -f "$file" ]] || {
        echo "Release metadata not found: $file" >&2
        exit 2
    }
done
[[ -n "$PUBLISHER_REVISION" ]] || {
    echo "Publisher revision must not be empty." >&2
    exit 2
}
[[ "$REPOSITORY_URL" =~ ^https://.+/$ ]] || {
    echo "Repository URL must be an absolute HTTPS URL ending in a slash." >&2
    exit 2
}
[[ "$SIGNING_KEY_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]] || {
    echo "Signing-key fingerprint must contain 40 hexadecimal characters." >&2
    exit 2
}
[[ "$ALLOW_OVERRIDE" == "true" || "$ALLOW_OVERRIDE" == "false" ]] || {
    echo "Allow-override must be true or false." >&2
    exit 2
}

candidate_tag="$(jq -er '.tag | strings | select(length > 0)' "$CANDIDATE_RELEASE")"
candidate_digest="$(jq -er '.asset_digest | strings | select(length > 0)' "$CANDIDATE_RELEASE")"
candidate_id="$(jq -er '.release_id | numbers' "$CANDIDATE_RELEASE")"
current_tag="$(jq -er '.tag | strings | select(length > 0)' "$CURRENT_RELEASE")"
current_digest="$(jq -er '.asset_digest | strings | select(length > 0)' "$CURRENT_RELEASE")"
current_id="$(jq -er '.release_id | numbers' "$CURRENT_RELEASE")"
current_revision="$(jq -r '.publisher_revision // empty' "$CURRENT_RELEASE")"
current_repository_url="$(jq -r '.repository_url // empty' "$CURRENT_RELEASE")"
current_signing_key_fingerprint="$(jq -r '.signing_key_fingerprint // empty' "$CURRENT_RELEASE")"

if [[ "${current_signing_key_fingerprint^^}" != "$SIGNING_KEY_FINGERPRINT" ]]; then
    echo "Refusing unsupported signing-key replacement." >&2
    exit 5
fi

if [[ "$ALLOW_OVERRIDE" == "true" ]]; then
    echo "publish"
    exit 0
fi

parse_semver() {
    local tag="$1"
    if [[ ! "$tag" =~ ^vscode-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        return 1
    fi
    printf '%s %s %s\n' \
        "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
}

if ! read -r candidate_major candidate_minor candidate_patch \
    < <(parse_semver "$candidate_tag"); then
    echo "Candidate is not a stable SemVer release: $candidate_tag" >&2
    exit 2
fi
if ! read -r current_major current_minor current_patch \
    < <(parse_semver "$current_tag"); then
    echo "Current publication is not a stable SemVer release: $current_tag" >&2
    exit 2
fi

if [[ "$candidate_tag" == "$current_tag" \
    && ( "$candidate_id" != "$current_id" || "$candidate_digest" != "$current_digest" ) ]]; then
    echo "Refusing automatically replaced release or asset for $candidate_tag." >&2
    exit 4
fi

is_newer=false
if (( candidate_major > current_major \
    || (candidate_major == current_major && candidate_minor > current_minor) \
    || (candidate_major == current_major && candidate_minor == current_minor \
        && candidate_patch > current_patch) )); then
    is_newer=true
fi
if [[ "$candidate_tag" != "$current_tag" && "$is_newer" != "true" ]]; then
    echo "Refusing automatic rollback from $current_tag to $candidate_tag." >&2
    exit 4
fi

if [[ "$candidate_tag" == "$current_tag" \
    && "$candidate_digest" == "$current_digest" \
    && "$current_revision" == "$PUBLISHER_REVISION" \
    && "$current_repository_url" == "$REPOSITORY_URL" ]]; then
    echo "skip"
else
    echo "publish"
fi
