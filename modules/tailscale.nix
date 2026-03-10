{
  services.tailscale = {
    enable = true;
    extraUpFlags = [
      "--login-server=https://hs.headpats.uk"
    ];
  };
}
