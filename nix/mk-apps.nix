{ lib
, writeShellApplication
, coreutils
, findutils
, dotnet-sdk
}:

let
  mkInstallApp =
    { name ? "install"
    , modPackages
    , description ? "Install Caves of Qud mod(s) into a Mods directory"
    }:
    let
      modIds = map (pkg: pkg.passthru.modId) modPackages;
      modListLabel = lib.concatStringsSep ", " modIds;
      pkg = writeShellApplication {
        inherit name;
        runtimeInputs = [ coreutils ];
        text = ''
          usage() {
            cat <<'EOF'
          Usage: nix run .#${name} -- [--symlink] [--mods-dir <path>] [<mods-dir>]

          ${description} (${modListLabel})

          Options:
            --mods-dir <path>  Target Caves of Qud Mods directory (or set COQ_MODS_DIR)
            --symlink          Symlink to the Nix store package instead of copying writable files
            -h, --help         Show this help message
          EOF
          }

          modsDir="''${COQ_MODS_DIR:-}"
          modsDirArgSet=false
          useSymlink=false

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --mods-dir)
                [ "$#" -ge 2 ] || { echo "Missing value for --mods-dir" >&2; exit 1; }
                modsDir="$2"
                modsDirArgSet=true
                shift 2
                ;;
              --symlink)
                useSymlink=true
                shift
                ;;
              -h|--help)
                usage
                exit 0
                ;;
              -*)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
              *)
                if [ "$modsDirArgSet" = true ]; then
                  echo "Unexpected extra argument: $1" >&2
                  usage >&2
                  exit 1
                fi
                modsDir="$1"
                modsDirArgSet=true
                shift
                ;;
            esac
          done

          if [ -z "$modsDir" ]; then
            echo "Error: provide a Mods directory path or set COQ_MODS_DIR." >&2
            usage >&2
            exit 1
          fi

          mkdir -p "$modsDir"

          install_one() {
            local modId="$1"
            local pkgModDir="$2"
            local targetDir="$modsDir/$modId"

            if [ -L "$targetDir" ]; then
              rm -f "$targetDir"
            elif [ -e "$targetDir" ]; then
              rm -rf "$targetDir"
            fi

            if [ "$useSymlink" = true ]; then
              ln -s "$pkgModDir" "$targetDir"
              echo "Symlinked $modId -> $pkgModDir at $targetDir"
            else
              mkdir -p "$targetDir"
              cp -r "$pkgModDir/." "$targetDir/"
              chmod -R u+w "$targetDir"
              echo "Installed $modId (writable copy) to $targetDir"
            fi
          }

          ${lib.concatMapStringsSep "\n" (modPkg:
            let
              id = modPkg.passthru.modId;
            in
            ''install_one ${lib.escapeShellArg id} ${lib.escapeShellArg "${modPkg}/share/qud-mods/${id}"}''
          ) modPackages}
        '';
      };
    in
    {
      type = "app";
      program = "${pkg}/bin/${name}";
      meta = { inherit description; };
    };

  mkDotnetRunner =
    { name
    , description
    , dotnetArgs
    , src
    , csproj
    , modRelDir
    , testCsproj ? null
    , workTreePaths ? [ ]
    }:
    let
      rawPaths =
        [ csproj ]
        ++ lib.optional (modRelDir != "") modRelDir
        ++ workTreePaths
        ++ lib.optional (testCsproj != null) testCsproj;
      copyPaths = lib.sort
        (a: b: builtins.stringLength a < builtins.stringLength b)
        (lib.unique rawPaths);

      dotnetSrc =
        if builtins.isPath src then
          if modRelDir == "" then
            lib.fileset.toSource {
              root = src;
              fileset = lib.fileset.fileFilter
                (file: !(lib.hasPrefix "." file.name))
                src;
            }
          else
            lib.fileset.toSource {
              root = src;
              fileset = lib.fileset.unions (map
                (rel:
                  let
                    full = src + "/${rel}";
                  in
                  if lib.pathIsDirectory full then
                    lib.fileset.fileFilter (file: !(lib.hasPrefix "." file.name)) full
                  else
                    full
                )
                copyPaths);
            }
        else
          src;

      pkg = writeShellApplication {
        inherit name;
        runtimeInputs = [ coreutils findutils dotnet-sdk ];
        text = ''
          usage() {
            cat <<'EOF'
          Usage: nix run .#${name} -- [--coq-dir <path>] [--coq-managed-dir <path>]

          ${description}

          Options:
            --coq-dir <path>          Path to Caves of Qud install directory (or set COQ_DIR)
            --coq-managed-dir <path>  Path to Caves of Qud Managed DLLs (or set COQ_MANAGED_DIR)
            -h, --help                Show this help message
          EOF
          }

          coqDir="''${COQ_DIR:-}"
          coqManagedDir="''${COQ_MANAGED_DIR:-}"

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --coq-dir)
                [ "$#" -ge 2 ] || { echo "Missing value for --coq-dir" >&2; exit 1; }
                coqDir="$2"
                shift 2
                ;;
              --coq-managed-dir)
                [ "$#" -ge 2 ] || { echo "Missing value for --coq-managed-dir" >&2; exit 1; }
                coqManagedDir="$2"
                shift 2
                ;;
              -h|--help)
                usage
                exit 0
                ;;
              *)
                echo "Unknown argument: $1" >&2
                usage >&2
                exit 1
                ;;
            esac
          done

          if [ -z "$coqDir" ] && [ -z "$coqManagedDir" ]; then
            echo "Error: provide --coq-dir / --coq-managed-dir or set COQ_DIR / COQ_MANAGED_DIR." >&2
            usage >&2
            exit 1
          fi

          if [ -f "$PWD/${csproj}" ]; then
            sourceRoot="$PWD"
          else
            sourceRoot="${dotnetSrc}"
          fi

          workDir="$(mktemp -d)"
          trap 'rm -rf "$workDir"' EXIT

          copy_rel() {
            local rel="$1"
            local srcPath="$sourceRoot/$rel"
            local dstPath="$workDir/$rel"
            if [ -e "$dstPath" ]; then
              return 0
            fi
            if [ ! -e "$srcPath" ]; then
              echo "Error: expected path '$rel' not found in $sourceRoot" >&2
              exit 1
            fi
            mkdir -p "$(dirname "$dstPath")"
            if [ -d "$srcPath" ]; then
              cp -r "$srcPath" "$dstPath"
            else
              cp "$srcPath" "$dstPath"
            fi
          }

          ${if modRelDir == "" then ''
            cp -r "$sourceRoot/." "$workDir/"
            rm -rf "$workDir/.git" "$workDir/result" "$workDir"/result-*
          '' else
            lib.concatMapStringsSep "\n" (p: ''copy_rel ${lib.escapeShellArg p}'') copyPaths
          }

          find "$workDir" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
          chmod -R u+w "$workDir"

          export DOTNET_NOLOGO=1
          export DOTNET_CLI_TELEMETRY_OPTOUT=1
          export DOTNET_CLI_HOME="$workDir/.dotnet"

          msbuildProps=()
          if [ -n "$coqDir" ]; then
            msbuildProps+=("-p:CoqDir=$coqDir")
          fi
          if [ -n "$coqManagedDir" ]; then
            msbuildProps+=("-p:CoqManagedDir=$coqManagedDir")
          fi

          cd "$workDir"
          exec dotnet ${dotnetArgs} "''${msbuildProps[@]}"
        '';
      };
    in
    {
      type = "app";
      program = "${pkg}/bin/${name}";
      meta = { inherit description; };
    };
in
{
  inherit mkInstallApp mkDotnetRunner;
}
