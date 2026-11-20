{ lib
, stdenvNoCC
, pname
, modDir
, extraFiles ? [ ]
}:

let
  manifestPath = modDir + "/manifest.json";
  manifest = builtins.fromJSON (builtins.readFile manifestPath);
  modId = manifest.ID;

  normalizedExtraFiles =
    if builtins.isList extraFiles then
      builtins.listToAttrs (map
        (p: {
          name = baseNameOf (toString p);
          value = p;
        })
        extraFiles)
    else
      extraFiles;

  stageExtraEntry = targetName: sourcePath:
    if lib.pathIsDirectory sourcePath then
      let
        filteredDir = lib.fileset.toSource {
          root = sourcePath;
          fileset = lib.fileset.fileFilter
            (file: !(lib.hasPrefix "." file.name))
            sourcePath;
        };
      in
      ''
        mkdir -p "$modDir/${targetName}"
        cp -r "${filteredDir}/." "$modDir/${targetName}/"
      ''
    else
      let
        stagedParent = lib.fileset.toSource {
          root = dirOf sourcePath;
          fileset = sourcePath;
        };
        fileName = baseNameOf (toString sourcePath);
      in
      ''
        mkdir -p "$(dirname "$modDir/${targetName}")"
        cp "${stagedParent}/${fileName}" "$modDir/${targetName}"
      '';
in
stdenvNoCC.mkDerivation {
  inherit pname;
  version = manifest.Version;

  src = lib.fileset.toSource {
    root = modDir;
    fileset = lib.fileset.fileFilter
      (file: !(lib.hasPrefix "." file.name))
      modDir;
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    modDir="$out/share/qud-mods/${modId}"
    mkdir -p "$modDir"
    cp -r . "$modDir/"

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList stageExtraEntry normalizedExtraFiles)}

    runHook postInstall
  '';

  passthru = {
    inherit manifest modId;
  };

  meta = {
    description = manifest.Description;
    platforms = lib.platforms.all;
  };
}
