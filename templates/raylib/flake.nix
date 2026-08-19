{
  description = "cubeforge-raylib — 3D block editor with Raylib + ImGui + Lua";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        mingw = pkgs.pkgsCross.mingwW64.buildPackages;
        mingwPkgs = pkgs.pkgsCross.mingwW64;

        imguiSrc = pkgs.fetchFromGitHub {
          owner = "ocornut";
          repo = "imgui";
          rev = "v1.92.4";
          hash = "sha256-DyQ2fh749S41UFdLto7TtxsnBsd7CBzAUFq36LeZZ5Y=";
        };

        luaSrc = pkgs.runCommand "lua-5.4-src" { } ''
          mkdir -p $out
          tar xzf ${pkgs.lua5_4.src} --strip-components=1 -C $out
        '';
      in {
        devShells.default = pkgs.mkShell {
          name = "cubeforge-raylib-dev";

          packages = with pkgs; [
            mingw.gcc
            mingw.binutils
            gnumake
            pkg-config
            python3
            lua5_4
            git
            zip
          ];

          buildInputs = with pkgs; [
            raylib
            libGL
            mesa
            libx11
            libxrandr
            libxinerama
            libxcursor
            libxi
            inter
            ipafont
            stb
          ];

          shellHook = ''
            export CF_ROOT=$PWD
            export IMGUI_DIR=${imguiSrc}
            export LUA_SRC=${luaSrc}
            export RAYLIB_INC=${pkgs.raylib}/include
            export RAYLIB_LIB=${pkgs.raylib}/lib
            export FONT_LATIN=${pkgs.inter}/share/fonts/truetype/InterVariable.ttf
            export FONT_CJK=${pkgs.ipafont}/share/fonts/truetype/ipag.ttf
            export STB_INC=${pkgs.stb}/include/stb

            # Windows cross: raylib import lib + runtime DLL from pkgsCross
            export RAYLIB_CROSS_INC=${mingwPkgs.raylib}/include
            export RAYLIB_CROSS_LIB=${mingwPkgs.raylib}/lib
            export RAYLIB_CROSS_DLL=${mingwPkgs.raylib}/bin/libraylib.dll
            # nixpkgs mingw raylib links GLFW dynamically — ship its DLL too
            export GLFW_CROSS_DLL=${mingwPkgs.glfw}/bin/glfw3.dll

            export MCFG_LIBDIR=$(x86_64-w64-mingw32-g++ -### -x c++ /dev/null -o /dev/null 2>&1 \
              | tr ' ' '\n' | grep -m1 -oE '^-L/nix/store/[^ ]*mcfgthread[^ ]*/lib' | cut -c3-)
            export MCFG_DLL=$(dirname "$MCFG_LIBDIR")/bin/libmcfgthread-2.dll

            export MINGW_CC=x86_64-w64-mingw32-gcc
            export MINGW_CXX=x86_64-w64-mingw32-g++

            echo "cubeforge-raylib dev shell ready"
            echo "  raylib:   ${pkgs.raylib}"
            echo "  imgui:    ${imguiSrc}"
            echo "  build:    make -C editor        # windows cross"
            echo "            make -C editor linux  # native linux"
          '';
        };

        packages = rec {
          cubeforge = pkgs.stdenv.mkDerivation {
            pname = "cubeforge";
            version = "1.0.0";
            src = ./.;

            nativeBuildInputs = [ pkgs.pkg-config pkgs.gnumake ];
            buildInputs = with pkgs; [
              raylib
              libGL
              mesa
              libx11
              libxrandr
              libxinerama
              libxcursor
              libxi
            ];

            buildPhase = ''
              make -C editor linux \
                IMGUI_DIR=${imguiSrc} \
                LUA_SRC=${luaSrc} \
                RAYLIB_INC=${pkgs.raylib}/include \
                RAYLIB_LIB=${pkgs.raylib}/lib \
                FONT_LATIN=${pkgs.inter}/share/fonts/truetype/InterVariable.ttf \
                FONT_CJK=${pkgs.ipafont}/share/fonts/truetype/ipag.ttf \
                STB_INC=${pkgs.stb}/include/stb
            '';

            installPhase = ''
              mkdir -p $out/bin $out/share/cubeforge/lua $out/share/cubeforge/tests $out/share/cubeforge/assets/fonts
              cp build/cubeforge-raylib $out/bin/cubeforge
              cp -r editor/lua/* $out/share/cubeforge/lua/
              cp -r editor/tests/* $out/share/cubeforge/tests/
              cp ${pkgs.inter}/share/fonts/truetype/InterVariable.ttf $out/share/cubeforge/assets/fonts/InterVariable.ttf
              cp ${pkgs.ipafont}/share/fonts/truetype/ipag.ttf $out/share/cubeforge/assets/fonts/ipag.ttf
            '';
          };
          default = cubeforge;
        };

        formatter = pkgs.nixfmt-rfc-style;
      });
}
