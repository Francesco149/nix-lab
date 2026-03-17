{ config, ... }:
let
  inherit (config) lab;
in
{
  # web ui to parse and analyze dmarc report zip's and a service that
  # automatically scans the postmaster's inbox for reports

  services.dmarc-analyzer = {
    enable = true;
    mailDir = "/var/vmail/${lab.domains.base}/${lab.mail.master}/mail";
    scanUser = config.mailserver.vmailUserName;
    port = lab.ports.dmarc-analyzer;
    listenHost = lab.lan.mail;
  };

  # only allow connections from code so that it's only reachable through caddy

  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s ${lab.lan.code} -d ${lab.lan.mail} \
      -p tcp --dport ${toString lab.ports.dmarc-analyzer} -j nixos-fw-accept
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -s ${lab.lan.code} -d ${lab.lan.mail} \
      -p tcp --dport ${toString lab.ports.dmarc-analyzer} -j nixos-fw-accept || true
  '';

}
