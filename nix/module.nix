{ flake-parts-lib, lib, ... }:

let
  inherit (flake-parts-lib) mkPerSystemOption;

  mkPackage = import ./mk-package.nix;
  mkZip = import ./mk-zip.nix;
  mkChecks = import ./mk-checks.nix;
  mkApps = import ./mk-apps.nix;

  modSubmodule = { name, ... }: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable outputs for this Caves of Qud mod.";
      };

      default = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Mark this mod as the default mod for unprefixed flake outputs (inferred automatically when only one mod is enabled).";
      };

      pname = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Package name for the mod derivation.";
      };

      src = lib.mkOption {
        type = lib.types.nullOr (lib.types.addCheck lib.types.unspecified (x:
          builtins.isPath x || (builtins.isAttrs x && x ? outPath)
        ));
        default = null;
        description = "Flake/repository root path (typically `./.`). Required when dotnet.enable is true and modDir is a subdirectory.";
      };

      modDir = lib.mkOption {
        type = lib.types.path;
        description = "Path to the mod directory containing manifest.json.";
      };

      extraFiles = lib.mkOption {
        type = lib.types.either
          (lib.types.listOf lib.types.path)
          (lib.types.attrsOf lib.types.path);
        default = [ ];
        description = "Extra files or directories to copy into the packaged mod directory (e.g. [ ./README.md ] or { \"README.md\" = ./README.md; }).";
      };

      zip = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to build a reproducible release zip archive package.";
        };
      };

      checks = {
        manifest.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to validate manifest.json fields.";
        };

        layout = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to validate packaged mod directory layout and dotfile absence.";
          };

          requiredFiles = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "manifest.json" ];
            description = "Relative paths expected inside the packaged mod directory.";
          };
        };

        zip.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to verify the zip archive contents match the mod package.";
        };
      };

      dotnet = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable C#/.NET check and test apps and include dotnet tooling in devShells.";
        };

        csproj = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Relative path from src to the mod .csproj file.";
        };

        testCsproj = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional relative path from src to the test .csproj file.";
        };

        testCommand = lib.mkOption {
          type = lib.types.enum [ "run" "test" ];
          default = "run";
          description = "dotnet subcommand used to execute testCsproj ('run' for console test runners, 'test' for xUnit/NUnit/MSTest).";
        };

        workTreePaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional relative paths from src to stage in the temporary dotnet working directory.";
        };
      };

      devShell = {
        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Extra packages to include in this mod's devShell.";
        };
      };
    };
  };
in
{
  options.perSystem = mkPerSystemOption ({ config, pkgs, ... }: {
    options.qudMods = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule modSubmodule);
      default = { };
      description = "Caves of Qud mods managed by qud-mod-nix.";
    };

    config =
      let
        enabledMods = lib.filterAttrs (_: m: m.enable) config.qudMods;
        enabledNames = lib.attrNames enabledMods;

        explicitDefaults = lib.attrNames (lib.filterAttrs (_: m: m.default) enabledMods);
        defaultModName =
          if lib.length explicitDefaults > 1 then
            throw "Multiple qudMods have default = true: ${lib.concatStringsSep ", " explicitDefaults}"
          else if lib.length explicitDefaults == 1 then
            builtins.head explicitDefaults
          else if lib.length enabledNames == 1 then
            builtins.head enabledNames
          else
            null;

        appsLib = pkgs.callPackage mkApps { };

        buildMod = name: modCfg:
          let
            modPackage = pkgs.callPackage mkPackage {
              inherit (modCfg) pname modDir extraFiles;
            };

            zipPackage =
              if modCfg.zip.enable then
                pkgs.callPackage mkZip { inherit modPackage; }
              else
                null;

            modChecks = mkChecks {
              inherit (pkgs) lib runCommand jq unzip diffutils;
              inherit modPackage zipPackage;
              checkPrefix = modCfg.pname;
              enableManifest = modCfg.checks.manifest.enable;
              enableLayout = modCfg.checks.layout.enable;
              requiredFiles = modCfg.checks.layout.requiredFiles;
              enableZip = modCfg.checks.zip.enable;
            };

            effectiveSrc =
              if modCfg.src != null then modCfg.src else modCfg.modDir;

            modRelDir =
              let
                srcStr = toString effectiveSrc;
                modDirStr = toString modCfg.modDir;
              in
              if modDirStr == srcStr then
                ""
              else if lib.hasPrefix "${srcStr}/" modDirStr then
                lib.removePrefix "${srcStr}/" modDirStr
              else
                throw "qudMods.${name}: modDir (${modDirStr}) must be inside src (${srcStr}) when dotnet.enable is true.";

            dotnetEnabled = modCfg.dotnet.enable;

            mkModApps = prefix:
              let
                appName = suffix: if prefix == "" then suffix else "${prefix}-${suffix}";
              in
              {
                install = appsLib.mkInstallApp {
                  name = appName "install";
                  modPackages = [ modPackage ];
                  description = "Install ${modPackage.passthru.modId} into a Caves of Qud Mods directory";
                };
              }
              // lib.optionalAttrs (dotnetEnabled && modCfg.dotnet.csproj != null) {
                check = appsLib.mkDotnetRunner {
                  name = appName "check";
                  description = "Compile ${modCfg.dotnet.csproj} against local Caves of Qud Managed DLLs";
                  dotnetArgs = "build ${lib.escapeShellArg modCfg.dotnet.csproj}";
                  src = effectiveSrc;
                  inherit (modCfg.dotnet) csproj workTreePaths;
                  inherit modRelDir;
                };
              }
              // lib.optionalAttrs (dotnetEnabled && modCfg.dotnet.csproj != null && modCfg.dotnet.testCsproj != null) {
                test =
                  let
                    testSubcmd =
                      if modCfg.dotnet.testCommand == "run" then
                        "run --project ${lib.escapeShellArg modCfg.dotnet.testCsproj}"
                      else
                        "test ${lib.escapeShellArg modCfg.dotnet.testCsproj}";
                  in
                  appsLib.mkDotnetRunner {
                    name = appName "test";
                    description = "Run ${modCfg.dotnet.testCsproj} unit tests against local Caves of Qud Managed DLLs";
                    dotnetArgs = testSubcmd;
                    src = effectiveSrc;
                    inherit (modCfg.dotnet) csproj testCsproj workTreePaths;
                    inherit modRelDir;
                  };
              };

            prefixedApps = mkModApps name;
            unprefixedApps = mkModApps "";

            dotnetPackages = lib.optionals dotnetEnabled [
              pkgs.dotnet-sdk
              pkgs.ilspycmd
            ];

            devShell = pkgs.mkShell {
              packages = dotnetPackages ++ modCfg.devShell.extraPackages;
            };
          in
          {
            inherit modPackage zipPackage modChecks prefixedApps unprefixedApps devShell dotnetPackages;
            extraShellPackages = modCfg.devShell.extraPackages;
          };

        builtMods = lib.mapAttrs buildMod enabledMods;

        allModPackages = lib.mapAttrsToList (_: b: b.modPackage) builtMods;

        perModPackages = lib.concatMapAttrs
          (name: b:
            { ${name} = b.modPackage; }
            // lib.optionalAttrs (b.zipPackage != null) { "${name}-zip" = b.zipPackage; }
          )
          builtMods;

        perModChecks = lib.concatMapAttrs
          (name: b:
            lib.mapAttrs' (chkName: chkDrv: lib.nameValuePair "${name}-${chkName}" chkDrv) b.modChecks
          )
          builtMods;

        perModApps = lib.concatMapAttrs
          (name: b:
            lib.mapAttrs' (appSuffix: appVal: lib.nameValuePair "${name}-${appSuffix}" appVal) b.prefixedApps
          )
          builtMods;

        perModDevShells = lib.mapAttrs (_: b: b.devShell) builtMods;

        defaultAliases =
          if defaultModName == null then
            { packages = { }; checks = { }; apps = { }; }
          else
            let
              b = builtMods.${defaultModName};
            in
            {
              packages =
                { default = b.modPackage; }
                // lib.optionalAttrs (b.zipPackage != null) { zip = b.zipPackage; };

              checks = b.modChecks;
              apps = b.unprefixedApps;
            };

        bulkInstallApp = lib.optionalAttrs (lib.length enabledNames > 1) {
          install-all = appsLib.mkInstallApp {
            name = "install-all";
            modPackages = allModPackages;
            description = "Install all configured Caves of Qud mods into a Mods directory";
          };
        };

        combinedDevShell = lib.optionalAttrs (enabledNames != [ ]) {
          default = pkgs.mkShell {
            packages = lib.unique (lib.concatMap (b: b.dotnetPackages ++ b.extraShellPackages) (lib.attrValues builtMods));
          };
        };
      in
      lib.mkIf (enabledNames != [ ]) {
        packages = perModPackages // defaultAliases.packages;
        checks = perModChecks // defaultAliases.checks;
        apps = perModApps // defaultAliases.apps // bulkInstallApp;
        devShells = perModDevShells // combinedDevShell;
      };
  });
}
