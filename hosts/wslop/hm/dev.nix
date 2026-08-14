# hosts/wslop/hm/dev.nix — PS2 reverse-engineering / translation toolchain.
# Used by the dokuro-translation-toolkit repo (WSL side). Everything a fresh
# session needs: disassemble SLPM_661.85 (mips:5900), run the .NET test
# harness, probe the emulator via tools/ps2dbg.py, inspect ISOs.
{ pkgs, ... }:
let
  # Host-native binutils targeting mipsel (like Debian's
  # binutils-mipsel-linux-gnu): pkgsCross.X.binutils builds for host=X, but
  # .buildPackages builds for the BUILD machine while targeting X — so
  # objdump runs on x86_64 and understands mips:5900 (EE MMI instructions).
  mipsel-binutils = pkgs.pkgsCross.mipsel-linux-gnu.buildPackages.binutils;
  # od.sh in the repo calls `mipsel-linux-gnu-objdump`; the nixpkgs wrapper
  # names it mipsel-unknown-linux-gnu-objdump. Alias it.
  mipsel-objdump-alias = pkgs.writeShellScriptBin "mipsel-linux-gnu-objdump" ''
    exec ${mipsel-binutils}/bin/mipsel-unknown-linux-gnu-objdump "$@"
  '';
in
{
  home.packages =
    with pkgs;
    [
      python3
      nodejs
      dotnet-sdk
      p7zip # 7z CLI for ISO inspection/extraction
      tinyxxd # hex dumps
      jq
      mipsel-binutils
      mipsel-objdump-alias
    ];
}
