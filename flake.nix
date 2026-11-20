{
  description = "Reusable flake-parts module for packaging, checking, testing, and installing Caves of Qud mods";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ ];

      flake.flakeModules = {
        default = ./nix/module.nix;
        qudMods = ./nix/module.nix;
      };
    };
}
