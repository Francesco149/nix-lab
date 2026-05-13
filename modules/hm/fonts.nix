{ config, pkgs, ... }:
let
  pxplus-ibm-vga8 = pkgs.stdenvNoCC.mkDerivation {
    name = "pxplus-ibm-vga8";
    src = pkgs.fetchurl {
      url = "https://github.com/pocketfood/Fontpkg-PxPlus_IBM_VGA8/raw/refs/heads/master/PxPlus_IBM_VGA8.ttf";
      hash = "sha256-RJjv9QBVKwkr8I/DFjP75f6S1pDInNEoR+z/7h3Hkwc=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/fonts/truetype
      cp $src $out/share/fonts/truetype/PxPlus_IBM_VGA8.ttf
    '';
  };

  jetbrains-mono-nerd = pkgs.stdenvNoCC.mkDerivation {
    name = "jetbrains-mono-nerd-font";
    src = pkgs.fetchurl {
      url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip";
      hash = "sha256-dvBf86zkikZKbKV5d5mHhP9727ZabZFdfkAc05J8STw=";
    };
    nativeBuildInputs = [ pkgs.unzip ];
    unpackPhase = ''
      unzip $src -d unpacked
    '';
    installPhase = ''
      mkdir -p $out/share/fonts/truetype
      cp unpacked/*.ttf $out/share/fonts/truetype/
    '';
  };
in
{
  home.packages = with pkgs; [
    pxplus-ibm-vga8
    jetbrains-mono-nerd
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" ];
      sansSerif = [ "Cantarell" ];
    };
  };
}
