#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly APP_ID="io.miragon.BpmnModeler"
readonly ARCH="x86_64"
readonly SOURCE_BRANCH="master"
readonly TARGET_BRANCH="stable"
readonly COLLECTION_ID="io.miragon.FlatpakRepository"
readonly MAX_SITE_SIZE_BYTES="${MAX_SITE_SIZE_BYTES:-950000000}"
readonly MAX_BUNDLE_SIZE_BYTES="${MAX_BUNDLE_SIZE_BYTES:-450000000}"

die() {
    echo "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<EOF
Usage: $0 \\
  --release-json <file> \\
  --bundle <file> \\
  --public-key <file> \\
  --gpg-key-id <fingerprint> \\
  --site-dir <directory> \\
  --base-url <https-url>
EOF
}

release_json=""
bundle=""
public_key=""
gpg_key_id=""
site_dir=""
base_url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release-json) release_json="${2:-}"; shift 2 ;;
        --bundle) bundle="${2:-}"; shift 2 ;;
        --public-key) public_key="${2:-}"; shift 2 ;;
        --gpg-key-id) gpg_key_id="${2:-}"; shift 2 ;;
        --site-dir) site_dir="${2:-}"; shift 2 ;;
        --base-url) base_url="${2:-}"; shift 2 ;;
        *) usage; die "Unknown argument: $1" ;;
    esac
done

for value in release_json bundle public_key gpg_key_id site_dir base_url; do
    [[ -n "${!value}" ]] || { usage; die "Missing --${value//_/-}."; }
done

for command in base64 flatpak gpg jq ostree python3 sha256sum; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required."
done

[[ -f "$release_json" ]] || die "Release metadata not found: $release_json"
[[ -f "$bundle" ]] || die "Flatpak bundle not found: $bundle"
[[ -f "$public_key" ]] || die "Public key not found: $public_key"
[[ "$gpg_key_id" =~ ^[0-9A-Fa-f]{40}$ ]] || die "A full GPG fingerprint is required."
[[ "$base_url" =~ ^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~/-]*)?$ ]] \
    || die "Invalid HTTPS base URL: $base_url"
base_url="${base_url%/}"

site_dir="$(realpath -m "$site_dir")"
[[ "$site_dir" == "$REPO_ROOT/site" ]] \
    || die "Site directory must be exactly $REPO_ROOT/site."

tag="$(jq -er '.tag | strings | select(length > 0)' "$release_json")"
published_at="$(jq -er '.published_at | strings | select(length > 0)' "$release_json")"
release_url="$(jq -er '.release_url | strings | select(length > 0)' "$release_json")"
asset_name="$(jq -er '.asset_name | strings | select(length > 0)' "$release_json")"
asset_url="$(jq -er '.asset_url | strings | select(length > 0)' "$release_json")"
asset_digest="$(jq -er '.asset_digest | strings | select(length > 0)' "$release_json")"
asset_size="$(jq -er '.asset_size | numbers' "$release_json")"

[[ "$tag" =~ ^vscode-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || die "Unexpected release tag: $tag"
[[ "$published_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] \
    || die "Unexpected release timestamp: $published_at"
[[ "$release_url" == "https://github.com/Miragon/bpmn-modeler/releases/tag/$tag" ]] \
    || die "Unexpected release URL: $release_url"
expected_asset_name="Miragon.BPMN.Modeler-${tag#vscode-v}-x86_64.flatpak"
[[ "$asset_name" == "$expected_asset_name" ]] \
    || die "Unexpected asset name: $asset_name"
[[ "$asset_url" == "https://github.com/Miragon/bpmn-modeler/releases/download/$tag/$asset_name" ]] \
    || die "Unexpected asset URL: $asset_url"
[[ "$asset_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || die "GitHub did not provide a valid SHA-256 asset digest."
(( asset_size > 0 && asset_size <= MAX_BUNDLE_SIZE_BYTES )) \
    || die "Bundle size $asset_size is outside the allowed range."

actual_digest="$(sha256sum "$bundle" | awk '{ print $1 }')"
[[ "$actual_digest" == "${asset_digest#sha256:}" ]] \
    || die "Bundle digest mismatch: expected ${asset_digest#sha256:}, got $actual_digest"
actual_size="$(stat -c %s "$bundle")"
[[ "$actual_size" == "$asset_size" ]] \
    || die "Bundle size mismatch: expected $asset_size, got $actual_size"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
source_repo="$work_dir/source-repo"
source_checkout="$work_dir/source-checkout"
public_gnupg_home="$work_dir/public-gnupg"
public_key_binary="$work_dir/miragon-flatpak.gpg"
repo_dir="$site_dir/repo"
source_ref="app/$APP_ID/$ARCH/$SOURCE_BRANCH"
target_ref="app/$APP_ID/$ARCH/$TARGET_BRANCH"

mkdir -m 700 "$public_gnupg_home"
gpg --homedir "$public_gnupg_home" --batch --import "$public_key" >/dev/null 2>&1
public_fingerprint="$(
    gpg --homedir "$public_gnupg_home" --batch --with-colons --fingerprint \
        | awk -F: '$1 == "fpr" { print $10; exit }'
)"
[[ "${public_fingerprint^^}" == "${gpg_key_id^^}" ]] \
    || die "Public key fingerprint does not match the signing key."
publisher_revision="$(
    "$REPO_ROOT/scripts/publisher-revision.sh" "$public_fingerprint"
)"
gpg --homedir "$public_gnupg_home" --batch --export "$public_fingerprint" \
    > "$public_key_binary"

gpg --batch --list-secret-keys "$gpg_key_id" >/dev/null 2>&1 \
    || die "The GPG secret key is not available in GNUPGHOME."

ostree init --repo="$source_repo" --mode=archive-z2
flatpak build-import-bundle --no-update-summary "$source_repo" "$bundle"

mapfile -t imported_app_refs < <(ostree refs --repo="$source_repo" | grep '^app/' || true)
if [[ ${#imported_app_refs[@]} -ne 1 || "${imported_app_refs[0]}" != "$source_ref" ]]; then
    printf 'Unexpected application refs in bundle:\n%s\n' "${imported_app_refs[*]:-(none)}" >&2
    exit 1
fi

ostree checkout --repo="$source_repo" --user-mode "$source_ref" "$source_checkout"

metadata_app_id="$(
    "$REPO_ROOT/scripts/read_flatpak_metadata.py" \
        "$source_checkout/metadata" Application name
)" \
    || die "Bundle metadata must contain one [Application] name."
metadata_runtime="$(
    "$REPO_ROOT/scripts/read_flatpak_metadata.py" \
        "$source_checkout/metadata" Application runtime
)" \
    || die "Bundle metadata must contain one [Application] runtime."
[[ "$metadata_app_id" == "$APP_ID" ]] \
    || die "Bundle metadata has an unexpected application ID."
[[ "$metadata_runtime" =~ ^org\.freedesktop\.Platform/$ARCH/[0-9]{2}\.[0-9]{2}$ ]] \
    || die "Bundle metadata has an unexpected runtime or architecture."

rm -rf "$site_dir"
mkdir -p "$repo_dir"
ostree init --repo="$repo_dir" --mode=archive-z2 --collection-id="$COLLECTION_ID"

flatpak build-commit-from \
    --src-repo="$source_repo" \
    --src-ref="$source_ref" \
    --untrusted \
    --update-appstream \
    --no-update-summary \
    --gpg-sign="$gpg_key_id" \
    --timestamp="$published_at" \
    --subject="Miragon BPMN Modeler ${tag#vscode-v}" \
    --body="Imported from $release_url" \
    "$repo_dir" "$target_ref"

flatpak build-update-repo \
    --title="Miragon Flatpak Repository" \
    --comment="Official Miragon BPMN Modeler packages" \
    --description="Official stable Flatpak repository for the Miragon BPMN Modeler." \
    --homepage="https://miragon.github.io/bpmn-modeler/" \
    --default-branch="$TARGET_BRANCH" \
    --collection-id="$COLLECTION_ID" \
    --deploy-collection-id \
    --gpg-import="$public_key_binary" \
    --gpg-sign="$gpg_key_id" \
    --generate-static-deltas \
    --prune \
    --prune-depth=0 \
    "$repo_dir"

gpg_key_base64="$(base64 --wrap=0 < "$public_key_binary")"
cp "$public_key_binary" "$site_dir/miragon-flatpak.gpg"

cat > "$site_dir/miragon.flatpakrepo" <<EOF
[Flatpak Repo]
Title=Miragon Flatpak Repository
Url=$base_url/repo/
Homepage=https://miragon.github.io/bpmn-modeler/
Comment=Official Miragon BPMN Modeler packages
Description=Official stable Flatpak repository for the Miragon BPMN Modeler.
DefaultBranch=$TARGET_BRANCH
GPGKey=$gpg_key_base64
EOF

cat > "$site_dir/$APP_ID.flatpakref" <<EOF
[Flatpak Ref]
Title=Miragon BPMN Modeler
Name=$APP_ID
Branch=$TARGET_BRANCH
Url=$base_url/repo/
SuggestRemoteName=miragon
Homepage=https://miragon.github.io/bpmn-modeler/
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
IsRuntime=false
GPGKey=$gpg_key_base64
EOF

jq \
    --arg branch "$TARGET_BRANCH" \
    --arg collection_id "$COLLECTION_ID" \
    --arg publisher_revision "$publisher_revision" \
    --arg repository_url "$base_url/repo/" \
    --arg signing_key_fingerprint "${public_fingerprint^^}" \
    '. + {
      branch: $branch,
      collection_id: $collection_id,
      publisher_revision: $publisher_revision,
      repository_url: $repository_url,
      signing_key_fingerprint: $signing_key_fingerprint
    }' \
    "$release_json" > "$site_dir/release.json"

cat > "$site_dir/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Miragon Flatpak Repository</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { max-width: 52rem; margin: 4rem auto; padding: 0 1.25rem; line-height: 1.6; }
    code { padding: .15rem .35rem; border-radius: .25rem; background: color-mix(in srgb, CanvasText 10%, Canvas); }
    pre { overflow-x: auto; padding: 1rem; border: 1px solid color-mix(in srgb, CanvasText 25%, Canvas); border-radius: .5rem; }
    a { color: LinkText; }
  </style>
</head>
<body>
  <h1>Miragon Flatpak Repository</h1>
  <p>Official stable x86_64 package for Miragon BPMN Modeler, currently <strong>${tag#vscode-v}</strong>.</p>
  <h2>Install</h2>
  <pre><code>flatpak install --user $base_url/$APP_ID.flatpakref</code></pre>
  <h2>Update</h2>
  <pre><code>flatpak update --user $APP_ID</code></pre>
  <p><a href="$APP_ID.flatpakref">Flatpak reference</a> | <a href="miragon.flatpakrepo">Repository descriptor</a> | <a href="$release_url">Source release</a></p>
</body>
</html>
EOF

ostree fsck --repo="$repo_dir"

test_user_dir="$work_dir/flatpak-user"
FLATPAK_USER_DIR="$test_user_dir" flatpak --user remote-add \
    --gpg-import="$public_key_binary" \
    --if-not-exists miragon-test "file://$repo_dir"
FLATPAK_USER_DIR="$test_user_dir" flatpak --user remote-info \
    miragon-test "$APP_ID" >/dev/null

site_size="$(du -sb "$site_dir" | awk '{ print $1 }')"
if (( site_size > MAX_SITE_SIZE_BYTES )); then
    die "Generated site is $site_size bytes and exceeds the $MAX_SITE_SIZE_BYTES byte limit."
fi

echo "Published $tag as $target_ref ($site_size bytes)."
