This repository contains a nix flake for [d3k](https://github.com/vercel-labs/dev3000) (dev3000). You can install d3k into your nix devshell with:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    d3k-nix.url = "github:hypervideo/d3k-nix";
  };

  outputs = { self, nixpkgs, flake-utils, d3k-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            d3k-nix.overlays.default
          ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            d3k
          ];
        };
      }
    );
}
```

This repository has an automatically running CI job that will update the `d3k` package to the latest version on a regular basis.
