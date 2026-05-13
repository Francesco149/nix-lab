{ ... }:
{
  xdg.configFile."mpv/mpv.conf".text = ''
    vo=gpu-next
    gpu-context=wayland
    hwdec=auto-safe
    keep-open=yes
  '';
}
