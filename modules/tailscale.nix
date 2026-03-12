{
  services.tailscale = {
    enable = true;
    extraUpFlags = [
      "--login-server=https://hs.headpats.uk"
      "--accept-dns=false"
      # local machines have no reason to use the tailscale
      # dns and it causes hangs in resolution sometimes.
    ];
  };
}
