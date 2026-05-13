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
in
{
  home.packages = [ pxplus-ibm-vga8 ];
  fonts.fontconfig.enable = true;
}
