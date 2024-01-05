{
  description = "Exploring safety in C++ through nixpkgs";

  inputs = {
    # nixpkgs.url = "github:RCoeurjoly/nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    poetry2nix = {
      # url = "github:nix-community/poetry2nix";
      url = "github:RCoeurjoly/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      inherit (poetry2nix.lib.mkPoetry2Nix { inherit pkgs; }) mkPoetryApplication mkPoetryEnv defaultPoetryOverrides;
      pypkgs-build-requirements = {
        wllvm = [ "setuptools" ];
      };
      p2n-overrides = defaultPoetryOverrides.extend (self: super:
        builtins.mapAttrs (package: build-requirements:
          (builtins.getAttr package super).overridePythonAttrs (old: {
            buildInputs = (old.buildInputs or [ ]) ++ (builtins.map (pkg: if builtins.isString pkg then builtins.getAttr pkg super else pkg) build-requirements);
          })
        ) pypkgs-build-requirements
      );
      packageName = "safety-for-cpp";
    in {

      # devShells.x86_64-linux.default = pkgs.mkShell {
      #   buildInputs = with pkgs; [ klee ];
      #   #inputsFrom = builtins.attrValues self.packages.${system};
      # };

      packages.x86_64-linux.get_sign =
        # Notice the reference to nixpkgs here.
        with import nixpkgs { system = "x86_64-linux"; };
        stdenv.mkDerivation {
          buildInputs = with pkgs; [ clang ];
          nativeBuildInputs = with pkgs; [ klee ];
          name = "get_sign";
          src = self;
          dontStrip = true;
          buildPhase = "clang -emit-llvm -c -g -O0 -Xclang -disable-O0-optnone ./src/get_sign.c";
          installPhase = "mkdir -p $out/bitcode; install -t $out/bitcode get_sign.bc";
        };


      packages.x86_64-linux.coreutils_src =
        # Notice the reference to nixpkgs here.
        with import nixpkgs { system = "x86_64-linux"; };
        pkgs.srcOnly {
          src = pkgs.coreutils.src;
          pname = pkgs.coreutils.meta.name;
          version = pkgs.coreutils.version;
        };

      packages.x86_64-linux.coreutils =
        with import nixpkgs { system = "x86_64-linux"; };
        stdenv.mkDerivation {
          # nativeBuildInputs = [ self.devShells.x86_64-linux.default ];
          nativeBuildInputs = [ self.packages.x86_64-linux.myapp pkgs.clang ];
          src = self.packages.x86_64-linux.coreutils_src;
          pname = pkgs.coreutils.meta.name;
          version = pkgs.coreutils.version;
          configurePhase = ''
        export LLVM_COMPILER=clang
        echo $LLVM_COMPILER
        CC=wllvm ./configure --prefix=$out --disable-nls CFLAGS="-g -O1 -Xclang -disable-llvm-passes -D__NO_STRING_INLINES  -D_FORTIFY_SOURCE=0 -U__OPTIMIZE__"
        '';

        };

      # Main package that uses the configured source
      packages.x86_64-linux.coreutils_extract =
        with import nixpkgs { system = "x86_64-linux"; };
        pkgs.stdenv.mkDerivation {
          nativeBuildInputs = [ self.packages.x86_64-linux.coreutils pkgs.clang pkgs.llvm ];
          buildInputs = [ pkgs.llvm ];
          pname = pkgs.coreutils.meta.name;
          version = pkgs.coreutils.version;
          src = self.packages.x86_64-linux.coreutils;
          installPhase = ''
    ls -l
    find bin/ -executable -type f | xargs -I '{}' extract-bc -l llvm-link-14 '{}'
    ls -l
    mkdir -p $out/bitcode; cp *.bc $out/bitcode/
  '';
        };
      packages.x86_64-linux.myapp = mkPoetryApplication {
        projectDir = self;
        overrides = p2n-overrides;
      };

      # devShells.x86_64-linux.default = mkPoetryEnv {
      #     projectDir = self;
      #     overrides = p2n-overrides;
      # };

      devShells.x86_64-linux.default = pkgs.mkShell {
        inputsFrom = [ self.packages.x86_64-linux.myapp ];
        packages = [ pkgs.poetry ];
      };

      packages.x86_64-linux.default = self.packages.x86_64-linux.coreutils_extract;

    };
}
