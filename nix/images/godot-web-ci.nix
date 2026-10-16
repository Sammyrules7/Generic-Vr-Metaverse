{ pkgs, baseTools, mkImageRoot, mkResolvedImage }:

let
  # The upstream package also contains Android, iOS, Linux, macOS, and Windows
  # templates. Copying only these files prevents those targets from becoming
  # runtime dependencies of the web-preview image. Discover the single inner
  # directory instead of recomposing <version>.stable, which broke when the
  # package renamed its version attribute and export_templates subdirectory.
  exportTemplates = pkgs.runCommand "godot-web-export-templates" { } ''
    templateDir="$(find "${pkgs.godot-export-templates-bin}/share/godot/export_templates" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    versionDir="$out/share/godot/export_templates/$(basename "$templateDir")"
    mkdir -p "$versionDir"
    cp "$templateDir"/web_*.zip "$versionDir/"
    cp "$templateDir/version.txt" "$versionDir/"
  '';
in
mkResolvedImage {
  name = "vr-platform-godot-web-ci";
  root = mkImageRoot "vr-platform-godot-web-ci-root" (baseTools ++ (with pkgs; [
    exportTemplates
    fontconfig
    godot_4
    s5cmd
  ]));
  env = [
    "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
    "PATH=/bin"
    "XDG_CONFIG_HOME=/tmp/godot-config"
    "XDG_DATA_HOME=/share"
  ];
}
