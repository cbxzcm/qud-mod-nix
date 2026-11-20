# qud-mod-nix

Reusable [flake-parts](https://flake.parts/) module for packaging, validating, zipping, testing, and installing **Caves of Qud** mods.

## Usage

In your mod's `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    qud-mod-nix.url = "github:cbxzcm/qud-mod-nix";
  };

  outputs = inputs@{ flake-parts, qud-mod-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ qud-mod-nix.flakeModules.default ];

      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];

      perSystem = {
        qudMods.my-mod = {
          src = ./.;
          modDir = ./MyMod;
          extraFiles = [ ./README.md ];

          # Optional C#/.NET support
          dotnet = {
            enable = true;
            csproj = "MyMod.csproj";
            testCsproj = "tests/MyMod.Tests.csproj";
            workTreePaths = [ "tests" ];
          };
        };
      };
    };
}
```

## Outputs Provided

For each enabled mod `<name>` under `qudMods`:
* `packages.<name>` — mod directory installed to `$out/share/qud-mods/<ID>/`
* `packages.<name>-zip` — deterministic `<ID>-<Version>.zip` release archive (when `zip.enable = true`)
* `checks.<name>-manifest`, `checks.<name>-package-layout`, `checks.<name>-zip-archive`
* `apps.<name>-install` — installs the mod into a `Mods` directory (`--mods-dir`, `COQ_MODS_DIR`, or `--symlink`)
* `apps.<name>-check`, `apps.<name>-test` — compiles/tests C# mods against local `COQ_DIR` / `COQ_MANAGED_DIR` (when `dotnet.enable = true`)
* `devShells.<name>` — includes `dotnet-sdk` and `ilspycmd` when `dotnet.enable = true`, plus `devShell.extraPackages`

When a single mod is configured (or one mod has `default = true`), unprefixed aliases (`packages.default`, `packages.zip`, `checks.manifest`, `checks.package-layout`, `checks.zip-archive`, `apps.install`, `apps.check`, `apps.test`) are also emitted. When multiple mods are configured, `apps.install-all` is added and `devShells.default` merges all shell packages.
