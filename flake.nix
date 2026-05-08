{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-mailserver.url = "gitlab:simple-nixos-mailserver/nixos-mailserver/main";
    disko.url = "github:nix-community/disko";
    llm-agents.url = "github:numtide/llm-agents.nix";

    nut.url = "git+file:///opt/src/nut";
    deploy-rs.url = "github:serokell/deploy-rs";
    home-manager.url = "github:nix-community/home-manager";
    dmarc-analyzer.url = "git+file:///opt/src/dmarc-analyzer";
    shigebot.url = "git+file:///opt/src/shigebot";
    lurk-monitor.url = "git+file:///opt/src/lurk-monitor";
    grammar-helper.url = "git+file:///opt/src/grammar-helper";

    nixos-mailserver.inputs.nixpkgs.follows = "nixpkgs";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    nut.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    dmarc-analyzer.inputs.nixpkgs.follows = "nixpkgs";
    shigebot.inputs.nixpkgs.follows = "nixpkgs";
    lurk-monitor.inputs.nixpkgs.follows = "nixpkgs";
    grammar-helper.inputs.nixpkgs.follows = "nixpkgs";
    llm-agents.inputs.nixpkgs.follows = "nixpkgs";

    nixos-mailserver.inputs.flake-compat.follows = "deploy-rs/flake-compat";
  };

  outputs =
    {
      self,
      nut,
      nixos-mailserver,
      dmarc-analyzer,
      disko,
      llm-agents,
      ...
    }@inputs:

    nut.lib.mf {
      inherit self inputs;
      dir = ./.;

      hosts.code = {
        modules = [
          ./modules/docker.nix
          ./modules/interactive.nix
          ./modules/tailscale-home-lan.nix
          ./modules/local.nix

          inputs.grammar-helper.nixosModules.default
          inputs.lurk-monitor.nixosModules.default

          # TODO: move to code.nix, somehow thread package through
          # TODO: allow hot reloading of config file
          inputs.shigebot.nixosModules.shigebot
          (
            { pkgs, ... }:
            {
              services.shigebot = {
                enable = true;
                package = inputs.shigebot.packages.${pkgs.stdenv.hostPlatform.system}.default;
                configFile = ./hosts/code/shigebot.toml;
                environmentFile = "/var/lib/secrets/shigebot-env";
              };
            }
          )
        ];

        hmModules.root = [
          ./modules/hm/common.nix
        ];
      };

      hosts.relay = [ ];

      hosts.mail = [
        nixos-mailserver.nixosModule
        inputs.dmarc-analyzer.nixosModules.dmarc-analyzer
        ./modules/local.nix
        ./modules/tailscale-home-lan.nix
      ];

      hosts.cold = [
        ./modules/local.nix
        ./modules/tailscale-home-lan.nix
        ./modules/initrd-unlock.nix
        ./modules/zfs.nix
        ./modules/backup-target.nix
      ];

      hosts.lame = {
        modules = [
          disko.nixosModules.disko
          ./modules/interactive.nix
          ./modules/local.nix
          ./modules/tailscale-home-lan.nix
          ./modules/initrd-unlock.nix
          ./modules/zfs.nix
          ./modules/backup-target.nix
        ];

        hmModules.root = [
          ./modules/hm/common.nix
        ];
      };

      modules = [
        (nut.lib.dumb "lab" (import ./lib/lab.nix))
        ./modules/common.nix
        ./modules/beszel.nix
        ./modules/nix.nix
      ];

      perSystem =
        { pkgs, ... }:
        {
          devShells.default = nut.lib.mkDevShell (import ./lib/devShell.nix { inherit pkgs; });
        };
    };

}
