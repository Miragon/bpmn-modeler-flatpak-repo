# Set Up the Flatpak Repository

This guide covers the one-time setup of the Flatpak signing key, GitHub Pages,
and the publishing workflow. Complete these steps before publishing the first
release.

All local key material is stored in the ignored `keys/` directory. Nothing from
that directory is committed to Git.

## Prerequisites

Install the required tools:

```bash
sudo apt install git gh gnupg
```

Authenticate the GitHub CLI:

```bash
gh auth login
```

Run the remaining commands from the root of this repository.

## 1. Create the Ignored Key Directory

Set the key directory and use an isolated GPG home so the repository key is not
mixed with your personal keys:

```bash
export REPOSITORY_ROOT="$(pwd -P)"
export MIRAGON_FLATPAK_KEY_DIR="$REPOSITORY_ROOT/keys"
export GNUPGHOME="$MIRAGON_FLATPAK_KEY_DIR/gnupg"

mkdir -p "$GNUPGHOME"
chmod 700 "$MIRAGON_FLATPAK_KEY_DIR" "$GNUPGHOME"
```

## 2. Generate the Signing Key

Create a dedicated 4096-bit RSA signing key without an expiration date:

```bash
gpg --quick-generate-key \
  "Miragon Flatpak Repository" \
  rsa4096 \
  sign \
  0
```

GPG prompts for a passphrase. Use a long, randomly generated passphrase and
store it in a password manager. You will add it to GitHub as the
`FLATPAK_GPG_PASSPHRASE` secret later.

Existing Flatpak installations permanently trust this key. Keep the same key
for all future releases.

## 3. Record the Full Fingerprint

Read and store the full key fingerprint:

```bash
export FLATPAK_GPG_FINGERPRINT="$(
  gpg --batch --with-colons --fingerprint "Miragon Flatpak Repository" \
    | awk -F: '$1 == "fpr" { print $10; exit }'
)"

printf '%s\n' "$FLATPAK_GPG_FINGERPRINT" \
  | tee "$MIRAGON_FLATPAK_KEY_DIR/miragon-flatpak.fingerprint"
```

The fingerprint must contain exactly 40 hexadecimal characters. Never use a
short key ID for the workflow configuration.

Pin the public fingerprint as repository configuration. This file lets the
workflow detect accidental or unauthorized replacement of the GitHub Secrets,
including during recovery publications:

```bash
mkdir -p config
printf '%s\n' "$FLATPAK_GPG_FINGERPRINT" \
  > config/signing-key.fingerprint
```

## 4. Export the Public Key

Export the public key into `keys/`:

```bash
gpg --batch --armor --export "$FLATPAK_GPG_FINGERPRINT" \
  > "$MIRAGON_FLATPAK_KEY_DIR/miragon-flatpak-public.asc"
```

Verify the exported fingerprint:

```bash
gpg --batch --show-keys --with-colons \
  "$MIRAGON_FLATPAK_KEY_DIR/miragon-flatpak-public.asc" \
  | awk -F: '$1 == "fpr" { print $10; exit }'
```

The output must match `$FLATPAK_GPG_FINGERPRINT`.

## 5. Export the Private Key

Export the password-protected private key into `keys/`:

```bash
gpg --armor --export-secret-keys "$FLATPAK_GPG_FINGERPRINT" \
  > "$MIRAGON_FLATPAK_KEY_DIR/miragon-flatpak-private.asc"

chmod 600 "$MIRAGON_FLATPAK_KEY_DIR/miragon-flatpak-private.asc"
```

GPG automatically creates a revocation certificate at:

```text
keys/gnupg/openpgp-revocs.d/<FINGERPRINT>.rev
```

Your local directory should now contain at least:

```text
keys/
├── gnupg/
├── miragon-flatpak.fingerprint
├── miragon-flatpak-private.asc
└── miragon-flatpak-public.asc
```

Back up the complete `keys/` directory to a second encrypted and access-
controlled location. Also store the passphrase in your password manager.

Losing the private key prevents you from publishing updates trusted by existing
installations.

## 6. Confirm That Only the Fingerprint Is Tracked

Check the Git working tree:

```bash
git status --short
git check-ignore -v keys/*
```

No file below `keys/` may appear as an untracked or staged Git file. Do not use
`git add -f` on this directory.

The public fingerprint configuration must be committed:

```bash
git add config/signing-key.fingerprint
```

The fingerprint is public information, not private key material.

## 7. Configure GitHub Pages and the Environment

Create the public repository `Miragon/bpmn-modeler-flatpak-repo`, add it as the
Git remote, and push the `main` branch.

Configure GitHub Pages:

1. Open **Settings** → **Pages**.
2. Select **GitHub Actions** under **Build and deployment**.
3. Open **Settings** → **Environments**.
4. Create or open the `github-pages` environment.
5. Under **Deployment branches and tags**, select **Selected branches and
   tags** and allow only the protected `main` branch. This restriction is
   mandatory because the environment contains the private signing key.
6. Configure a repository ruleset for `main` that requires pull requests and
   review before changes to the workflow or pinned fingerprint can be merged.
7. Strongly consider adding required reviewers to the `github-pages`
   environment. This adds an approval gate before a workflow can access the
   signing secrets.

## 8. Configure the Private-Key Secrets

Upload the private key to the `github-pages` environment:

```bash
gh secret set --env github-pages FLATPAK_GPG_PRIVATE_KEY \
  < "$MIRAGON_FLATPAK_KEY_DIR/miragon-flatpak-private.asc"
```

Upload the passphrase without storing it in shell history or a plaintext file:

```bash
read -rsp "GPG passphrase: " FLATPAK_GPG_PASSPHRASE
printf '%s' "$FLATPAK_GPG_PASSPHRASE" \
  | gh secret set --env github-pages FLATPAK_GPG_PASSPHRASE
unset FLATPAK_GPG_PASSPHRASE
printf '\n'
```

Verify the environment secrets:

```bash
gh secret list --env github-pages
```

The output must include these names:

```text
FLATPAK_GPG_PRIVATE_KEY
FLATPAK_GPG_PASSPHRASE
```

GitHub does not display secret values after they are stored.

## 9. Start the First Publication

The first run requires an explicit policy override because GitHub Pages does
not have an existing `release.json` yet:

```bash
gh workflow run publish-flatpak.yml \
  -f allow_policy_override=true
```

Watch the workflow:

```bash
gh run watch
```

The workflow can publish only when a stable
`vscode-v<MAJOR>.<MINOR>.<PATCH>` release contains this exact asset:

```text
Miragon.BPMN.Modeler-<MAJOR>.<MINOR>.<PATCH>-x86_64.flatpak
```

## 10. Verify the Published Repository

Add and inspect the Flatpak remote:

```bash
flatpak remote-add --user --if-not-exists miragon \
  https://miragon.github.io/bpmn-modeler-flatpak-repo/miragon.flatpakrepo

flatpak --user remote-info miragon io.miragon.BpmnModeler
```

Install and run the application:

```bash
flatpak install --user miragon io.miragon.BpmnModeler
flatpak run io.miragon.BpmnModeler
```

Install later updates with:

```bash
flatpak update --user io.miragon.BpmnModeler
```

## Operations Notes

- The scheduled workflow checks for a new release every six hours.
- Routine manual and scheduled runs reject downgrades and replaced assets.
- An intentional rollback requires an explicit tag and
  `allow_policy_override=true`.
- Never replace the signing key directly. Key rotation requires a transition
  signed by both keys and is not automated by the current publisher.
- Never change `config/signing-key.fingerprint` to recover from a failed
  publish. It is the pinned trust anchor used to prevent unsupported key
  replacement.
- Keep the encrypted backup after configuring GitHub Secrets.
- Treat everyone with access to the `github-pages` environment secrets as a
  Flatpak release administrator.
