{ osConfig, ... }:
let
  inherit (osConfig.lab) colors;
  c = colors;
in
{
  xdg.configFile."fuzzel/fuzzel.ini".text = ''
    [main]
    font=PxPlus IBM VGA8:size=12
    prompt=
    lines=12
    width=50
    horizontal-pad=8
    vertical-pad=4
    line-height=16
    inner-pad=4
    show-actions=no

    [colors]
    background=${c.base00}ff
    text=${c.base04}ff
    match=${c.base0B}ff
    selection=${c.base04}ff
    selection-text=${c.base00}ff
    border=${c.base01}ff

    [border]
    width=2
    radius=0
  '';
}
