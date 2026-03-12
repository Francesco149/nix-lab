{
  # simple on-demand caching of nixos packages.
  # to use, add:'
  #
  #   nix.settings.substituters = [
  #     "https://cache.box.headpats.uk"
  #   ];

  services.nginx = {
    enable = true;

    appendHttpConfig = ''
      proxy_cache_path /var/cache/nginx/nix
        levels=1:2
        keys_zone=nix_cache:100m
        max_size=200g
        inactive=365d
        use_temp_path=off;
    '';

    virtualHosts."cache.box.headpats.uk" = {
      listen = [
        {
          # make sure we are also listening on dockerhost
          addr = "0.0.0.0";
          port = 8765;
        }
      ];

      locations."/" = {
        proxyPass = "https://cache.nixos.org";
        extraConfig = ''
          proxy_cache nix_cache;
          proxy_cache_valid 200 365d;
          proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
          proxy_ignore_headers Cache-Control Expires;
          proxy_cache_lock on;
          proxy_ssl_server_name on;
        '';
      };
    };
  };
}
