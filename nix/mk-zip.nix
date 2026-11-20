{ lib
, stdenvNoCC
, zip
, modPackage
}:

let
  inherit (modPackage.passthru) manifest modId;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "${modPackage.pname}-zip";
  version = modPackage.version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zip ];

  installPhase = ''
    runHook preInstall

    export TZ=UTC
    staging="$(mktemp -d)"
    trap 'rm -rf "$staging"' EXIT

    cp -r "${modPackage}/share/qud-mods/${modId}" "$staging/${modId}"
    chmod -R u+w "$staging/${modId}"
    find "$staging/${modId}" -exec touch -d "@''${SOURCE_DATE_EPOCH:-315532800}" {} +

    mkdir -p "$out"
    (
      cd "$staging"
      find "${modId}" | LC_ALL=C sort | zip -@ -X "$out/${modId}-${finalAttrs.version}.zip"
    )

    runHook postInstall
  '';

  meta = {
    description = "${manifest.Description} (release zip archive)";
    platforms = lib.platforms.all;
  };
})
