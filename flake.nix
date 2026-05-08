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

    nut.lib.mf [
      {
        inherit self inputs;
        dir = ./.;

        modules = [
          (nut.lib.dumb "lab" (import ./lib/lab.nix))
          ./modules/common.nix
          ./modules/beszel.nix
          ./modules/nix.nix
        ];

        hosts = {
          code = [ ];
          mail = [ ];
          relay = [ ];
          cold = [ ];
          lame = [ ];
        };

        perSystem =
          { pkgs, ... }:
          {
            devShells.default = nut.lib.mkDevShell (import ./lib/devShell.nix { inherit pkgs; });
          };
      }

      {
        modules = [
          ./modules/local.nix
          ./modules/tailscale-home-lan.nix
        ];

        hosts = {
          code.modules = [
            ./modules/docker.nix
          ];

          mail.modules = [
            nixos-mailserver.nixosModule
            inputs.dmarc-analyzer.nixosModules.dmarc-analyzer
          ];

          cold = [ ];
          lame.modules = [
            disko.nixosModules.disko
          ];
        };
      }

      {
        modules = [
          ./modules/interactive.nix
        ];

        hmModules.root = [
          ./modules/hm/common.nix
        ];

        hosts = {
          code = [ ];
          lame = [ ];
        };
      }

      {
        modules = [
          ./modules/initrd-unlock.nix
          ./modules/zfs.nix
          ./modules/backup-target.nix
        ];

        hosts = {
          cold = [ ];
          lame = [ ];
        };
      }

      {
        hosts.code.modules = [
          inputs.grammar-helper.nixosModules.default
          inputs.lurk-monitor.nixosModules.default
          inputs.shigebot.nixosModules.shigebot
        ];
      }
    ];

}
