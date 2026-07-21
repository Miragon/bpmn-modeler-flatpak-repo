#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly READER="$REPO_ROOT/scripts/read_flatpak_metadata.py"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

valid="$work_dir/valid"
cat > "$valid" <<'EOF'
[Application]
name = io.miragon.BpmnModeler
runtime=org.freedesktop.Platform/x86_64/25.08
EOF
[[ "$("$READER" "$valid" Application name)" == "io.miragon.BpmnModeler" ]]
[[ "$("$READER" "$valid" Application runtime)" == "org.freedesktop.Platform/x86_64/25.08" ]]

duplicate="$work_dir/duplicate"
cat > "$duplicate" <<'EOF'
[Application]
name=io.miragon.BpmnModeler
name = unexpected.value
runtime=org.freedesktop.Platform/x86_64/25.08
EOF
if "$READER" "$duplicate" Application name >/dev/null 2>&1; then
    echo "Metadata reader accepted a whitespace-obscured duplicate key." >&2
    exit 1
fi

repeated_section="$work_dir/repeated-section"
cat > "$repeated_section" <<'EOF'
[Application]
name=io.miragon.BpmnModeler
runtime=org.freedesktop.Platform/x86_64/25.08
[Application]
runtime=org.freedesktop.Platform/x86_64/24.08
EOF
if "$READER" "$repeated_section" Application runtime >/dev/null 2>&1; then
    echo "Metadata reader accepted duplicate keys across repeated sections." >&2
    exit 1
fi

trailing_whitespace="$work_dir/trailing-whitespace"
cat > "$trailing_whitespace" <<'EOF'
[Application]
name=io.miragon.BpmnModeler 
runtime=org.freedesktop.Platform/x86_64/25.08
EOF
[[ "$("$READER" "$trailing_whitespace" Application name)" \
    == "io.miragon.BpmnModeler " ]]

malformed="$work_dir/malformed"
cat > "$malformed" <<'EOF'
[Application]
name=io.miragon.BpmnModeler
this line is invalid
runtime=org.freedesktop.Platform/x86_64/25.08
EOF
if "$READER" "$malformed" Application name >/dev/null 2>&1; then
    echo "Metadata reader accepted a malformed GLib key file." >&2
    exit 1
fi

echo "Flatpak metadata tests passed."
