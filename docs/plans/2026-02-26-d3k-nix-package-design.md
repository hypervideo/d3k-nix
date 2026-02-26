# d3k-nix Package Design

## Goal

Wrap the `dev3000` npm package (CLI: `d3k`) as a Nix flake, providing it as a package and overlay for use in devShells. Mirror the portless-nix structure.

## Context

- npm package name: `dev3000` (binary aliases: `dev3000`, `d3k`)
- Source: https://github.com/vercel-labs/dev3000
- Upstream nix repo: https://github.com/hypervideo/d3k-nix
- Reference repo: portless-nix (same org)
- Current version: 0.0.168
- License: MIT
- Node.js: >= 18.0.0 (engines), >= 22.12.0 (recommended)
- Has platform-specific optional deps (`@d3k/darwin-arm64`, `@d3k/linux-x64`)

## Files

| File | Purpose |
|------|---------|
| `default.nix` | Package derivation using `buildNpmPackage` |
| `flake.nix` | Flake with overlay, package, and devShell outputs |
| `package-lock.json` | Vendored production-only npm lockfile |
| `scripts/update-d3k.sh` | Update script to check npm for new versions |
| `.github/workflows/update-d3k.yml` | Weekly CI to auto-create PRs on updates |
| `README.md` | Usage documentation |

## default.nix

- Fetch tarball from `https://registry.npmjs.org/dev3000/-/dev3000-{version}.tgz`
- Strip devDependencies with `jq`
- Copy in vendored `package-lock.json`
- `buildNpmPackage` with `dontNpmBuild = true`
- `nodejs_22` (recommended by upstream)
- Wrap `d3k` binary
- License: MIT, Platforms: linux + darwin

## flake.nix

- Overlay: `d3k = final.callPackage ./default.nix {}`
- Per-system: `packages.default`, `devShells.default`

## CI

- Weekly cron (Monday 6 AM UTC) + manual trigger
- Check npm latest, download tarball, compute hashes, update default.nix, create PR
- Use `nodejs_22` and `prefetch-npm-deps`

## Key difference from portless-nix

- No extra runtime PATH wrapping needed (no openssl equivalent)
- Larger dependency tree but same `buildNpmPackage` approach
- Package name (`dev3000`) differs from binary name (`d3k`)
