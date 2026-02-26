# d3k-nix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Package the `dev3000` npm package as a Nix flake providing `d3k` as a package, overlay, and devShell.

**Architecture:** Follow the exact same structure as `portless-nix`. Use `buildNpmPackage` with a vendored production-only `package-lock.json`, fetch the pre-built npm tarball, and strip devDependencies. Provide overlay + per-system outputs.

**Tech Stack:** Nix flakes, `buildNpmPackage`, nodejs_22, GitHub Actions

**Reference repo:** `/Users/robert/projects/shuttle/utils/portless-nix` — mirror its structure for all files.

---

### Task 1: Generate vendored package-lock.json

**Files:**
- Create: `package-lock.json`

**Step 1: Download the npm tarball and generate production-only lockfile**

```bash
WORK_DIR=$(mktemp -d)
curl -sfL https://registry.npmjs.org/dev3000/-/dev3000-0.0.168.tgz -o "$WORK_DIR/dev3000.tgz"
mkdir -p "$WORK_DIR/package"
tar -xzf "$WORK_DIR/dev3000.tgz" -C "$WORK_DIR/package" --strip-components=1

# Strip devDependencies
jq 'del(.devDependencies)' "$WORK_DIR/package/package.json" > "$WORK_DIR/package/package.json.tmp"
mv "$WORK_DIR/package/package.json.tmp" "$WORK_DIR/package/package.json"

# Generate production-only lockfile
cd "$WORK_DIR/package" && npm install --package-lock-only --ignore-scripts 2>/dev/null
```

**Step 2: Copy the lockfile into the repo**

```bash
cp "$WORK_DIR/package/package-lock.json" /Users/robert/projects/shuttle/utils/d3k-nix/package-lock.json
rm -rf "$WORK_DIR"
```

**Step 3: Verify the lockfile looks correct**

Check it's lockfileVersion 3 and has no devDependencies in the root package entry.

**Step 4: Commit**

```bash
git add package-lock.json
git commit -m "chore: add vendored production package-lock.json for dev3000 0.0.168"
```

---

### Task 2: Create default.nix package derivation

**Files:**
- Create: `default.nix`
- Reference: `/Users/robert/projects/shuttle/utils/portless-nix/default.nix`

**Step 1: Compute the source hash**

```bash
WORK_DIR=$(mktemp -d)
curl -sfL https://registry.npmjs.org/dev3000/-/dev3000-0.0.168.tgz -o "$WORK_DIR/dev3000.tgz"
nix hash path --mode flat "$WORK_DIR/dev3000.tgz"
```

Save this hash for use in default.nix.

**Step 2: Compute the npm deps hash**

```bash
nix shell nixpkgs#prefetch-npm-deps -c prefetch-npm-deps /Users/robert/projects/shuttle/utils/d3k-nix/package-lock.json
```

Save this hash for use in default.nix.

**Step 3: Write default.nix**

Model after portless-nix `default.nix` exactly. Key differences:
- `pname = "d3k"`
- `version = "0.0.168"`
- Tarball URL: `https://registry.npmjs.org/dev3000/-/dev3000-${version}.tgz`
- Use `nodejs_22` instead of `nodejs_20`
- No `postInstall` wrapping (no openssl needed)
- `mainProgram = "d3k"`
- `license = licenses.mit`
- `description` from npm: "AI-powered development tools with browser monitoring and skill integration"
- `homepage = "https://github.com/vercel-labs/dev3000"`

```nix
{
  lib,
  buildNpmPackage,
  fetchurl,
  runCommand,
  jq,
  nodejs_22,
}:

let
  version = "0.0.168";

  srcWithLock = runCommand "d3k-src-with-lock" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/dev3000/-/dev3000-${version}.tgz";
        hash = "<SRC_HASH>";
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies)' $out/package.json > $out/package.json.tmp
    mv $out/package.json.tmp $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in

buildNpmPackage {
  pname = "d3k";
  inherit version;

  src = srcWithLock;

  npmDepsHash = "<NPM_DEPS_HASH>";

  dontNpmBuild = true;
  nodejs = nodejs_22;

  meta = with lib; {
    description = "AI-powered development tools with browser monitoring and skill integration";
    homepage = "https://github.com/vercel-labs/dev3000";
    license = licenses.mit;
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "d3k";
  };
}
```

Replace `<SRC_HASH>` and `<NPM_DEPS_HASH>` with values from steps 1 and 2.

**Step 4: Commit**

```bash
git add default.nix
git commit -m "feat: add d3k package derivation"
```

---

### Task 3: Update flake.nix with overlay and outputs

**Files:**
- Modify: `flake.nix`
- Reference: `/Users/robert/projects/shuttle/utils/portless-nix/flake.nix`

**Step 1: Write flake.nix**

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    {
      overlays.default = final: prev: {
        d3k = final.callPackage ./default.nix { };
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
      in
      {
        packages.default = pkgs.d3k;

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.d3k ];
        };
      }
    );
}
```

**Step 2: Build and verify**

```bash
nix build
```

Expected: builds successfully, produces `result/bin/d3k`.

**Step 3: Test the binary runs**

```bash
./result/bin/d3k --help
```

Expected: shows help output.

**Step 4: Update flake.lock**

```bash
nix flake update
```

**Step 5: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat: add flake with overlay, package, and devShell"
```

---

### Task 4: Create update script

**Files:**
- Create: `scripts/update-d3k.sh`
- Reference: `/Users/robert/projects/shuttle/utils/portless-nix/scripts/update-portless.sh`

**Step 1: Write the update script**

Same pattern as `update-portless.sh` but for `dev3000`:
- npm registry URL: `https://registry.npmjs.org/dev3000/latest`
- Tarball URL: `https://registry.npmjs.org/dev3000/-/dev3000-${LATEST_VERSION}.tgz`
- Uses `nodejs_22` for npm operations
- File name: `d3k.tgz` in temp dir

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CURRENT_VERSION=$(grep 'version = "' "$REPO_DIR/default.nix" | head -1 | sed 's/.*version = "\(.*\)";/\1/')
echo "Current version: $CURRENT_VERSION"

LATEST_VERSION=$(curl -sf https://registry.npmjs.org/dev3000/latest | jq -r '.version')
echo "Latest npm version: $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating from $CURRENT_VERSION to $LATEST_VERSION..."

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL_URL="https://registry.npmjs.org/dev3000/-/dev3000-${LATEST_VERSION}.tgz"
curl -sfL "$TARBALL_URL" -o "$WORK_DIR/dev3000.tgz"

SRC_HASH=$(nix hash path --mode flat "$WORK_DIR/dev3000.tgz")
echo "Source hash: $SRC_HASH"

mkdir -p "$WORK_DIR/package"
tar -xzf "$WORK_DIR/dev3000.tgz" -C "$WORK_DIR/package" --strip-components=1
jq 'del(.devDependencies)' "$WORK_DIR/package/package.json" > "$WORK_DIR/package/package.json.tmp"
mv "$WORK_DIR/package/package.json.tmp" "$WORK_DIR/package/package.json"

(cd "$WORK_DIR/package" && npm install --package-lock-only --ignore-scripts 2>/dev/null)

NPM_DEPS_HASH=$(prefetch-npm-deps "$WORK_DIR/package/package-lock.json" 2>/dev/null)
echo "NPM deps hash: $NPM_DEPS_HASH"

sed "s|version = \"$CURRENT_VERSION\"|version = \"$LATEST_VERSION\"|" "$REPO_DIR/default.nix" \
  | sed "s|hash = \".*\"|hash = \"$SRC_HASH\"|" \
  | sed "s|npmDepsHash = \".*\"|npmDepsHash = \"$NPM_DEPS_HASH\"|" \
  > "$REPO_DIR/default.nix.tmp"
mv "$REPO_DIR/default.nix.tmp" "$REPO_DIR/default.nix"

cp "$WORK_DIR/package/package-lock.json" "$REPO_DIR/package-lock.json"

echo "Updated d3k to $LATEST_VERSION"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "VERSION=$LATEST_VERSION" >> "$GITHUB_OUTPUT"
  echo "UPDATED=true" >> "$GITHUB_OUTPUT"
fi
```

**Step 2: Make executable**

```bash
chmod +x scripts/update-d3k.sh
```

**Step 3: Commit**

```bash
git add scripts/update-d3k.sh
git commit -m "feat: add update script for d3k"
```

---

### Task 5: Create CI workflow

**Files:**
- Create: `.github/workflows/update-d3k.yml`
- Reference: `/Users/robert/projects/shuttle/utils/portless-nix/.github/workflows/update-portless.yml`

**Step 1: Write the workflow**

Same as portless but with `nodejs_22` and d3k naming:

```yaml
name: Update d3k

on:
  schedule:
    - cron: "0 6 * * 1"
  workflow_dispatch: {}

permissions:
  contents: write
  pull-requests: write

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: cachix/install-nix-action@v31
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes

      - name: Check for updates
        id: update
        run: |
          nix shell nixpkgs#curl nixpkgs#jq nixpkgs#nodejs_22 nixpkgs#prefetch-npm-deps \
            -c bash scripts/update-d3k.sh

      - name: Build updated package
        if: steps.update.outputs.UPDATED == 'true'
        run: nix build

      - name: Create Pull Request
        if: steps.update.outputs.UPDATED == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          VERSION="${{ steps.update.outputs.VERSION }}"
          BRANCH="update-d3k-${VERSION}"

          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

          git checkout -b "$BRANCH"
          git add default.nix package-lock.json
          git commit -m "chore: update d3k to ${VERSION}"
          git push origin "$BRANCH"

          if ! gh pr list --head "$BRANCH" --json number --jq '.[0].number' | grep -q .; then
            gh pr create \
              --title "chore: update d3k to ${VERSION}" \
              --body "Automated update of d3k to version ${VERSION}." \
              --base main
          fi
```

**Step 2: Commit**

```bash
git add .github/workflows/update-d3k.yml
git commit -m "feat: add CI workflow for automated d3k updates"
```

---

### Task 6: Write README.md

**Files:**
- Create: `README.md`
- Reference: `/Users/robert/projects/shuttle/utils/portless-nix/README.md`

**Step 1: Write README**

```markdown
This repository contains a nix flake for [d3k](https://github.com/vercel-labs/dev3000) (dev3000). You can install d3k into your nix devshell with:

\```nix
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
\```

This repository has an automatically running CI job that will update the `d3k` package to the latest version on a regular basis.
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage instructions"
```

---

### Task 7: Final verification and push

**Step 1: Full clean build**

```bash
nix build --rebuild
```

**Step 2: Verify binary works**

```bash
./result/bin/d3k --help
```

**Step 3: Verify devShell works**

```bash
nix develop -c d3k --help
```

**Step 4: Push to upstream**

```bash
git push origin main
```
