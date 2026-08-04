# Miragon Flatpak Repository

This repository publishes the official `x86_64` Flatpak package for the
[Miragon BPMN Modeler](https://github.com/Miragon/bpmn-modeler) as a signed,
updateable OSTree repository on GitHub Pages.

The publisher downloads the Flatpak bundle attached to the newest stable
`vscode-v*` release, verifies GitHub's SHA-256 asset digest, validates the app
ID and architecture, and creates a new signed `stable` ref. It never trusts or
directly publishes refs from the release bundle.

The upstream GitHub repository remains the provenance trust boundary: the asset
and its digest are both supplied by `Miragon/bpmn-modeler`. After the first
publication, scheduled runs reject replacement of that release asset. A future
source workflow can strengthen first-publication provenance with GitHub artifact
attestations.

## Install

Install the bpmn modeler in the user space with:

```bash
flatpak remote-add --user --if-not-exists miragon https://miragon.github.io/bpmn-modeler-flatpak-repo/miragon.flatpakrepo

flatpak install --user miragon io.miragon.BpmnModeler
```

Alternatively, install the bpmn modeler globally with:

```bash
sudo flatpak remote-add --user --if-not-exists miragon https://miragon.github.io/bpmn-modeler-flatpak-repo/miragon.flatpakrepo

sudo flatpak install --user miragon io.miragon.BpmnModeler
```

## Run

Run the bpmn modeler with:

```bash
flatpak run io.miragon.BpmnModeler
```

## Update

Update the bpmn modeler with:

```bash
flatpak update --user io.miragon.BpmnModeler
```

## Publication model

GitHub Pages has a published-site limit of 1 GB and a soft bandwidth limit of
100 GB per month. Each deployment is therefore rebuilt from only the selected
release instead of preserving an unbounded release history. Flatpak clients can
still update from an older installed commit to the current `stable` ref, but an
update may be larger than a repository that retains deltas between every
release.

The generated site contains:

```text
repo/                                  Signed OSTree repository
miragon.flatpakrepo                    Remote descriptor
io.miragon.BpmnModeler.flatpakref      One-command installer
miragon-flatpak.gpg                    Binary public signing key
release.json                           Published source release metadata
index.html                             Installation instructions
```

Generated files are deployed directly as a GitHub Pages artifact and are not
committed to Git.

## Local checks

Release selection has a fixture-based test:

```bash
./tests/select-release-test.sh
./tests/publication-policy-test.sh
./tests/publisher-revision-test.sh
./tests/flatpak-metadata-test.sh
```

When the Freedesktop 25.08 SDK and runtime are installed, an end-to-end test
builds two minimal bundles and exercises import, signing, static deltas,
installation, and a signed update between independently rebuilt repositories:

```bash
./tests/publish-release-test.sh
```

The live resolver can be run independently. Exit status `3` means that no
matching release exists yet:

```bash
./scripts/resolve-release.sh
./scripts/resolve-release.sh vscode-v1.6.0
```

`scripts/publish-release.sh` performs the following checks before a Pages
artifact can be uploaded:

- GitHub asset digest verification
- exact release, asset, app ID, architecture, and runtime validation
- untrusted OSTree import into a temporary repository
- public/private signing key fingerprint match
- OSTree `fsck`
- signed Flatpak remote lookup using an isolated user installation
- generated site size below 950 MB

## Key rotation

Do not replace the public key directly. Existing Flatpak clients trust the old
key and would reject a repository signed only by a new key. A rotation requires
a transition release signed by both keys and descriptors containing both public
keys before the old key can be retired. The current publisher intentionally
supports one key only, so key rotation requires extending and testing the
publisher before running the generator again.
