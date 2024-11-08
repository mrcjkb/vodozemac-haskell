{
  nixConfig = {
    extra-substituters = "https://cache.ners.ch/haskell";
    extra-trusted-public-keys = "haskell:WskuxROW5pPy83rt3ZXnff09gvnu80yovdeKDw5Gi3o=";
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    inline-rust = {
      url = "github:ners/inline-rust";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs = inputs:
    with builtins;
    let
      inherit (inputs.nixpkgs) lib;
      foreach = xs: f: with lib; foldr recursiveUpdate { } (
        if isList xs then map f xs
        else if isAttrs xs then mapAttrsToList f xs
        else throw "foreach: expected list or attrset but got ${typeOf xs}"
      );
      sourceFilter = root: with lib.fileset; toSource {
        inherit root;
        fileset = fileFilter
          (file: any file.hasExt [
            "cabal"
            "hs"
            "hsc"
            "lock"
            "md"
            "rs"
            "toml"
          ])
          root;
      };
      pname = "vodozemac";
      src = sourceFilter ./.;
      ghcsFor = pkgs: with lib; foldlAttrs
        (acc: name: hp:
          let
            version = getVersion hp.ghc;
            majorMinor = versions.majorMinor version;
            ghcName = "ghc${replaceStrings ["."] [""] majorMinor}";
          in
          if hp ? ghc && ! acc ? ${ghcName} && versionAtLeast version "8.10" && versionOlder version "9.11"
          then acc // { ${ghcName} = hp; }
          else acc
        )
        { }
        pkgs.haskell.packages;
      hpsFor = pkgs: { default = pkgs.haskellPackages; } // ghcsFor pkgs;
      overlay = lib.composeManyExtensions [
        inputs.inline-rust.overlays.default
        (final: prev: {
          vodozemac_hs =
            let
              crane = inputs.crane.mkLib final;
              strictDeps = true;
              cargoArtifacts = crane.buildDepsOnly { inherit src strictDeps; };
              package = crane.buildPackage { inherit src strictDeps cargoArtifacts; };
            in
              package;

          haskell = prev.haskell // {
            packageOverrides = with prev.haskell.lib.compose; lib.composeManyExtensions [
              prev.haskell.packageOverrides
              (hfinal: hprev: {
                ${pname} = hfinal.callCabal2nix pname src { };
              })
            ];
          };
        })
      ];
    in
    {
      overlays.default = overlay;
    }
    //
    foreach inputs.nixpkgs.legacyPackages
      (system: pkgs':
        let
          pkgs = pkgs'.extend overlay;
          hps = hpsFor pkgs;
          libs = pkgs.buildEnv {
            name = "${pname}-libs";
            paths = map (hp: hp.${pname}) (attrValues hps);
            pathsToLink = [ "/lib" ];
          };
          docs = pkgs.haskell.lib.documentationTarball hps.default.${pname};
          sdist = pkgs.haskell.lib.sdistTarball hps.default.${pname};
          docsAndSdist = pkgs.linkFarm "${pname}-docsAndSdist" { inherit docs sdist; };
        in
        {
          formatter.${system} = pkgs.nixpkgs-fmt;
          legacyPackages.${system} = pkgs;
          packages.${system}.default = pkgs.symlinkJoin {
            name = "${pname}-all";
            paths = [ libs docsAndSdist ];
            inherit (hps.default.syntax) meta;
          };
          devShells.${system} =
            foreach hps (ghcName: hp: {
              ${ghcName} = hp.shellFor {
                packages = ps: [ ps.${pname} ];
                nativeBuildInputs = with pkgs'; with haskellPackages; [
                  cabal-install
                  cargo
                  fourmolu
                  rust-analyzer
                ] ++ lib.optionals (lib.versionAtLeast (lib.getVersion hp.ghc) "9.2") [
                  hp.haskell-language-server
                ];
              };
            });
        }
      );
}
