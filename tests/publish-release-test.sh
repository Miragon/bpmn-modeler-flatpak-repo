#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly APP_ID="io.miragon.BpmnModeler"

for command in flatpak gpg jq ostree sha256sum; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "$command is required." >&2
        exit 2
    }
done

work_dir="$(mktemp -d)"
site_dir="$REPO_ROOT/site"
if [[ -e "$site_dir" ]]; then
    echo "Refusing to replace existing test site: $site_dir" >&2
    exit 2
fi
trap 'rm -rf "$work_dir" "$site_dir"' EXIT

gnupg_home="$work_dir/gnupg"
public_key="$work_dir/public.asc"
mkdir -m 700 "$gnupg_home"

gpg --homedir "$gnupg_home" --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "Flatpak Publisher Test" rsa2048 sign 1d
fingerprint="$(
    gpg --homedir "$gnupg_home" --batch --with-colons --fingerprint \
        | awk -F: '$1 == "fpr" { print $10; exit }'
)"
gpg --homedir "$gnupg_home" --batch --armor --export "$fingerprint" > "$public_key"

build_bundle() {
    local version="$1"
    local message="$2"
    local bundle="$3"
    local build_dir="$work_dir/build-$version"
    local source_repo="$work_dir/source-repo-$version"

    flatpak build-init --arch=x86_64 \
        "$build_dir" "$APP_ID" org.freedesktop.Sdk org.freedesktop.Platform 25.08
    flatpak build "$build_dir" sh -c \
        "install -d /app/bin && printf '#!/bin/sh\\necho $message\\n' > /app/bin/miragon-bpmn-modeler && chmod 755 /app/bin/miragon-bpmn-modeler"
    flatpak build-finish --command=miragon-bpmn-modeler "$build_dir"
    flatpak build-export --disable-fsync "$source_repo" "$build_dir" master
    flatpak build-bundle "$source_repo" "$bundle" "$APP_ID" master
}

write_release() {
    local version="$1"
    local release_id="$2"
    local published_at="$3"
    local bundle="$4"
    local release_json="$5"
    local tag="vscode-v$version"
    local asset_name="Miragon.BPMN.Modeler-$version-x86_64.flatpak"
    local digest
    digest="$(sha256sum "$bundle" | awk '{ print $1 }')"

    jq -n \
        --argjson release_id "$release_id" \
        --arg tag "$tag" \
        --arg published_at "$published_at" \
        --arg release_url "https://github.com/Miragon/bpmn-modeler/releases/tag/$tag" \
        --arg asset_name "$asset_name" \
        --arg asset_url "https://github.com/Miragon/bpmn-modeler/releases/download/$tag/$asset_name" \
        --arg asset_digest "sha256:$digest" \
        --argjson asset_size "$(stat -c %s "$bundle")" \
        '{
          release_id: $release_id,
          tag: $tag,
          published_at: $published_at,
          release_url: $release_url,
          asset_name: $asset_name,
          asset_url: $asset_url,
          asset_digest: $asset_digest,
          asset_size: $asset_size
        }' > "$release_json"
}

publish_release() {
    local release_json="$1"
    local bundle="$2"

    GNUPGHOME="$gnupg_home" "$REPO_ROOT/scripts/publish-release.sh" \
        --release-json "$release_json" \
        --bundle "$bundle" \
        --public-key "$public_key" \
        --gpg-key-id "$fingerprint" \
        --site-dir "$site_dir" \
        --base-url "https://miragon.github.io/bpmn-modeler-flatpak-repo"
}

first_bundle="$work_dir/Miragon.BPMN.Modeler-9.9.9-x86_64.flatpak"
first_release="$work_dir/release-9.9.9.json"
build_bundle "9.9.9" "first" "$first_bundle"
write_release "9.9.9" 999 "2026-08-05T12:00:00Z" "$first_bundle" "$first_release"
publish_release "$first_release" "$first_bundle"

[[ -f "$site_dir/io.miragon.BpmnModeler.flatpakref" ]]
[[ -f "$site_dir/miragon.flatpakrepo" ]]
[[ "$(jq -r '.tag' "$site_dir/release.json")" == "vscode-v9.9.9" ]]
[[ "$(jq -r '.publisher_revision' "$site_dir/release.json")" \
    == "$("$REPO_ROOT/scripts/publisher-revision.sh" "$fingerprint")" ]]
[[ "$(jq -r '.signing_key_fingerprint' "$site_dir/release.json")" \
    == "$fingerprint" ]]
ostree refs --repo="$site_dir/repo" \
    | grep -Fxq "app/$APP_ID/x86_64/stable"

client_dir="$work_dir/flatpak-client"
FLATPAK_USER_DIR="$client_dir" flatpak --user remote-add \
    --gpg-import="$site_dir/miragon-flatpak.gpg" \
    miragon-update-test "file://$site_dir/repo"
FLATPAK_USER_DIR="$client_dir" flatpak --user install \
    --noninteractive --no-deps miragon-update-test "$APP_ID"
first_commit="$(
    FLATPAK_USER_DIR="$client_dir" flatpak --user info --show-commit "$APP_ID"
)"

second_bundle="$work_dir/Miragon.BPMN.Modeler-10.0.0-x86_64.flatpak"
second_release="$work_dir/release-10.0.0.json"
build_bundle "10.0.0" "second" "$second_bundle"
write_release "10.0.0" 1000 "2026-08-06T12:00:00Z" "$second_bundle" "$second_release"
publish_release "$second_release" "$second_bundle"

FLATPAK_USER_DIR="$client_dir" flatpak --user update \
    --noninteractive --no-deps "$APP_ID"
second_commit="$(
    FLATPAK_USER_DIR="$client_dir" flatpak --user info --show-commit "$APP_ID"
)"
published_commit="$(
    ostree rev-parse --repo="$site_dir/repo" "app/$APP_ID/x86_64/stable"
)"
[[ "$first_commit" != "$second_commit" ]]
[[ "$second_commit" == "$published_commit" ]]

echo "Flatpak publication and update test passed."
