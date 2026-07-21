#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-Miragon/bpmn-modeler}"
readonly GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
readonly REQUESTED_TAG="${1:-}"

if [[ ! "$SOURCE_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "Invalid SOURCE_REPOSITORY: $SOURCE_REPOSITORY" >&2
    exit 2
fi

if [[ -n "$REQUESTED_TAG" \
    && ! "$REQUESTED_TAG" =~ ^vscode-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Invalid release tag: $REQUESTED_TAG" >&2
    exit 2
fi

for command in curl jq; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "$command is required." >&2
        exit 2
    fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
releases_file="$work_dir/releases.json"

curl_args=(
    --fail
    --silent
    --show-error
    --location
    --retry 3
    --connect-timeout 15
    --max-time 120
    --speed-limit 1024
    --speed-time 30
    --header "Accept: application/vnd.github+json"
    --header "X-GitHub-Api-Version: 2022-11-28"
)

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
fi

if [[ -n "$REQUESTED_TAG" ]]; then
    curl "${curl_args[@]}" \
        "$GITHUB_API_URL/repos/$SOURCE_REPOSITORY/releases/tags/$REQUESTED_TAG" \
        | jq '[.]' > "$releases_file"
else
    printf '[]\n' > "$releases_file"
    page=1

    while true; do
        page_file="$work_dir/releases-$page.json"
        merged_file="$work_dir/releases-merged.json"

        curl "${curl_args[@]}" \
            "$GITHUB_API_URL/repos/$SOURCE_REPOSITORY/releases?per_page=100&page=$page" \
            > "$page_file"

        if ! jq -e 'type == "array"' "$page_file" >/dev/null; then
            echo "GitHub returned an invalid releases response." >&2
            exit 2
        fi

        jq -s '.[0] + .[1]' "$releases_file" "$page_file" > "$merged_file"
        mv "$merged_file" "$releases_file"

        result_count="$(jq 'length' "$page_file")"
        if (( result_count < 100 )); then
            break
        fi
        ((page += 1))
    done
fi

selected_release="$(
    jq --arg requested_tag "$REQUESTED_TAG" \
        -f "$REPO_ROOT/scripts/select-release.jq" \
        "$releases_file"
)"

if [[ "$selected_release" == "null" ]]; then
    if [[ -n "$REQUESTED_TAG" ]]; then
        echo "Release $REQUESTED_TAG has no unique x86_64 Flatpak asset." >&2
    else
        echo "No published vscode-v* release with an x86_64 Flatpak asset found." >&2
    fi
    exit 3
fi

printf '%s\n' "$selected_release"
