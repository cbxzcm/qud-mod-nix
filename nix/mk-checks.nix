{ lib
, runCommand
, jq
, unzip
, diffutils
, modPackage
, zipPackage ? null
, checkPrefix ? modPackage.pname
, enableManifest ? true
, enableLayout ? true
, requiredFiles ? [ "manifest.json" ]
, enableZip ? true
}:

let
  inherit (modPackage.passthru) modId;
  inherit (modPackage) version;
in
lib.optionalAttrs enableManifest
  {
    manifest = runCommand "${checkPrefix}-check-manifest"
      {
        nativeBuildInputs = [ jq ];
      }
      ''
        manifestPath="${modPackage}/share/qud-mods/${modId}/manifest.json"
        jq -e '
          (.ID | type == "string" and length > 0) and
          (.Title | type == "string" and length > 0) and
          (.Description | type == "string" and length > 0) and
          (.Version | type == "string" and length > 0) and
          (.Author | type == "string" and length > 0) and
          .ID == "${modId}" and
          .Version == "${version}"
        ' "$manifestPath" > /dev/null
        touch "$out"
      '';
  }
// lib.optionalAttrs enableLayout {
  package-layout = runCommand "${checkPrefix}-check-layout" { } ''
    modDir="${modPackage}/share/qud-mods/${modId}"
    test -f "$modDir/manifest.json"
    ${lib.concatMapStringsSep "\n" (relPath: ''
      test -e "$modDir/"${lib.escapeShellArg relPath} || {
        echo "Missing required path in $modDir: ${relPath}" >&2
        exit 1
      }
    '') requiredFiles}
    if find "$modDir" -mindepth 1 -name '.*' | grep -q .; then
      echo "Unexpected dotfiles found in $modDir" >&2
      exit 1
    fi
    touch "$out"
  '';
}
// lib.optionalAttrs (enableZip && zipPackage != null) {
  zip-archive = runCommand "${checkPrefix}-check-zip"
    {
      nativeBuildInputs = [ unzip diffutils ];
    }
    ''
      zipFile="${zipPackage}/${modId}-${version}.zip"
      test -f "$zipFile"

      extracted="$(mktemp -d)"
      trap 'rm -rf "$extracted"' EXIT
      unzip -q "$zipFile" -d "$extracted"

      diff -ru "${modPackage}/share/qud-mods/${modId}" "$extracted/${modId}"
      touch "$out"
    '';
}
