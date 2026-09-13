{ pkgs, baseTools, mkImageRoot, mkResolvedImage }:

let
  # The upstream package also contains Android, iOS, Linux, macOS, and Windows
  # templates. Copying only these files prevents those targets from becoming
  # runtime dependencies of the web-preview image.
  exportTemplates = pkgs.runCommand "godot-web-export-templates" { } ''
    versionDir="$out/share/godot/export_templates/4.7.2.stable"
    mkdir -p "$versionDir"
    cp ${pkgs.godot-export-templates-bin}/share/godot/export_templates/4.7.2.stable/web_*.zip "$versionDir/"
    cp ${pkgs.godot-export-templates-bin}/share/godot/export_templates/4.7.2.stable/version.txt "$versionDir/"
  '';
in
mkResolvedImage {
  name = "vr-platform-godot-web-ci";
  root = mkImageRoot "vr-platform-godot-web-ci-root" (baseTools ++ (with pkgs; [
    exportTemplates
    fontconfig
    godot_4
  ]));
  env = [
    "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
    "PATH=/bin"
    "XDG_CONFIG_HOME=/tmp/godot-config"
    "XDG_DATA_HOME=/share"
  ];
}
