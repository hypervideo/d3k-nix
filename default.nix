{
  lib,
  buildNpmPackage,
  fetchurl,
  runCommand,
  jq,
  nodejs_22,
}:

let
  version = "0.0.171";

  srcWithLock = runCommand "d3k-src-with-lock" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/dev3000/-/dev3000-${version}.tgz";
        hash = "sha256-XOIW+iqJ8P8ccwYrevLjFrUToZP63YziKHTGT9tPxsg=";
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

  npmDepsHash = "sha256-Iic+BJ8/0hpoQPipexoRAJGIc/qC0xvxXjfQCJ+k5fU=";

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
