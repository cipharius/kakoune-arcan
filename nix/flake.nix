# The flake resides in a subdirectory as it should not copy the whole checkout to the nix store
# Context: https://github.com/NixOS/nix/issues/3121

rec {
  description = "kakoune-arcan development environment";

  inputs = {
    systems.url = "github:nix-systems/default";

    zig-x86_64-linux = {
      url = "https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz";
      flake = false;
    };
    zig-aarch64-linux = {
      url = "https://ziglang.org/download/0.13.0/zig-linux-aarch64-0.13.0.tar.xz";
      flake = false;
    };
    zig-x86_64-darwin = {
      url = "https://ziglang.org/download/0.13.0/zig-macos-x86_64-0.13.0.tar.xz";
      flake = false;
    };
    zig-aarch64-darwin = {
      url = "https://ziglang.org/download/0.13.0/zig-macos-aarch64-0.13.0.tar.xz";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    systems,
    ...
  } @ deriviations: let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    devShell = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      zig-version = "0.14.0";
      zig-source = deriviations."zig-${system}".outPath;
      zig = pkgs.stdenv.mkDerivation rec {
        pname = "zig";
        version = zig-version;
        src = zig-source;

        installPhase = ''
          mkdir -p "$out/bin"
          cp zig "$out/bin"
          cp -r lib "$out"
          cp -r doc "$out"
        '';

        meta = with pkgs.lib; {
          homepage = "https://ziglang.org/";
          description = "General-purpose programming language and toolchain for maintaining robust, optimal, and reusable software";
          license = licenses.mit;
          platforms = platforms.unix;
        };
      };
    in
      pkgs.mkShell {
        nativeBuildInputs = [ zig ];
        buildInputs = [
            pkgs.mesa
            pkgs.mesa_glu
            pkgs.SDL2
            pkgs.libxkbcommon
            pkgs.libdrm
            pkgs.xorg.libX11
            pkgs.xorg.libXcursor
            pkgs.xorg.libXext
            pkgs.xorg.libXfixes
            pkgs.xorg.libXi
            pkgs.xorg.libXrandr
        ];
      });
  };
}
