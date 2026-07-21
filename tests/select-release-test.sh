#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly FIXTURE="$REPO_ROOT/tests/fixtures/releases.json"
readonly FILTER="$REPO_ROOT/scripts/select-release.jq"

select_release() {
    jq --arg requested_tag "${1:-}" -f "$FILTER" "$FIXTURE"
}

latest="$(select_release)"
[[ "$(jq -r '.tag' <<< "$latest")" == "vscode-v1.6.0" ]]
[[ "$(jq -r '.asset_name' <<< "$latest")" == "Miragon.BPMN.Modeler-1.6.0-x86_64.flatpak" ]]
[[ "$(jq -r '.asset_digest' <<< "$latest")" == "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" ]]

requested="$(select_release "vscode-v1.5.0")"
[[ "$(jq -r '.tag' <<< "$requested")" == "vscode-v1.5.0" ]]

[[ "$(select_release "vscode-v1.5.5")" == "null" ]]
[[ "$(jq -r '.tag' <<< "$(select_release "vscode-v1.4.0")")" == "vscode-v1.4.0" ]]

echo "Release selection tests passed."
