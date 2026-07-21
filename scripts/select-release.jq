def flatpak_assets($version):
  [
    .assets[]?
    | select(.name == "Miragon.BPMN.Modeler-\($version)-x86_64.flatpak")
  ];

[
  .[]
  | select(.draft == false and .prerelease == false)
  | select(.tag_name | test("^vscode-v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
  | select($requested_tag == "" or .tag_name == $requested_tag)
]
| sort_by(.published_at)
| reverse
| .[0] // null
| if . == null then
    null
  else
    . as $release
    | ($release.tag_name | ltrimstr("vscode-v")) as $version
    | flatpak_assets($version) as $assets
    | if ($assets | length) != 1 then
        null
      else
        $assets[0] as $asset
        | {
            release_id: $release.id,
            tag: $release.tag_name,
            published_at: $release.published_at,
            release_url: $release.html_url,
            asset_name: $asset.name,
            asset_url: $asset.browser_download_url,
            asset_digest: ($asset.digest // ""),
            asset_size: $asset.size
          }
      end
  end
