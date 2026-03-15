{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nut.url = "path:/opt/src/nut";
    deploy-rs.url = "github:serokell/deploy-rs";
    home-manager.url = "github:nix-community/home-manager";
    nixos-mailserver.url = "gitlab:simple-nixos-mailserver/nixos-mailserver/master";

    nut.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-mailserver.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nut,
      nixos-mailserver,
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
        ];

        hmModules.root = [
          ./modules/hm/common.nix
        ];
      };

      hosts.relay = [
        ./modules/beszel.nix
      ];

      hosts.mail = [
        nixos-mailserver.nixosModule
        ./modules/local.nix
        ./modules/tailscale-home-lan.nix
      ];

      modules = [
        (nut.lib.dumb "lab" (import ./lib/lab.nix))
        ./modules/common.nix
      ];

      perSystem =
        { pkgs, ... }:
        {
          devShells.default = nut.lib.mkDevShell (import ./lib/devShell.nix { inherit pkgs; });
        };
    };

}
