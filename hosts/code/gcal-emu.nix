# gcal-emu — synthetic Google calendar/mail test-board for the SYGNAS「らき☆マス」
# launcher, hosted on `code` behind Caddy so the XP Time Machine can reach it during
# a probe run (the Time Machine's own NixOS courier is offline while XP is booted).
#
# The launcher speaks plain http:// to www.google.com (MFC WinINet, HTTP/1.0, no TLS),
# so XP's hosts redirects www.google.com -> code and Caddy's `http://www.google.com`
# vhost (in caddy.nix) reverse-proxies to this localhost service. Calendar only —
# POP3 mail isn't HTTP so Caddy can't front it; deferred (needs a TCP route + the
# launcher's [Mail] config).
#
# Canonical source of gcal_emu.py: /opt/src/LuckyMasterEN/tools/gcal-emu/ — the copy
# here is a vendored mirror (re-sync if that changes). This whole module is testing
# scaffolding; the end goal is a native XP-local build (see the project's next-builds).
#
# Flip the bubble live (no restart — the script re-reads the control file per request):
#   ssh code 'echo calendar=none > /var/lib/gcal-emu/scenario.conf'
# Captured request log (the exact event-feed URL the binary builds):
#   ssh code 'cat /var/lib/gcal-emu/gcal-emu.log'
{
  config,
  pkgs,
  ...
}:
{
  systemd.services.gcal-emu = {
    description = "synthetic Google calendar/mail test-board (らき☆マス launcher)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart =
        "${pkgs.python3}/bin/python3 ${./gcal-emu/gcal_emu.py} "
        + "--bind 127.0.0.1 --http ${toString config.lab.ports.gcal-emu} --no-pop";
      DynamicUser = true;
      StateDirectory = "gcal-emu"; # /var/lib/gcal-emu: scenario.conf + gcal-emu.log
      WorkingDirectory = "/var/lib/gcal-emu";
      Restart = "on-failure";
    };
  };
}
