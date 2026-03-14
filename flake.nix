{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nut.url = "path:/opt/src/nut";
    deploy-rs.url = "github:serokell/deploy-rs";
    home-manager.url = "github:nix-community/home-manager";

    nut.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nut, ... }@inputs:

    nut.lib.mf {
      inherit self inputs;
      dir = ./.;

      hosts.code = {
        modules = [
          ./modules/docker.nix
          ./modules/nix.nix
          ./modules/system-interactive.nix
        ];

        hmModules.root = [
          ./modules/hm/git.nix
          ./modules/hm/misc.nix
        ];
      };

      hosts.relay = [ ./modules/beszel.nix ];

      modules = [
        (nut.lib.dumb "lab" (import ./lib/lab.nix))
        ./modules/system.nix
        ./modules/tailscale.nix
        ./modules/ssh.nix
      ];

      perSystem =
        { pkgs, ... }:
        {
          devShells.default = nut.lib.mkDevShell (import ./lib/devShell.nix { inherit pkgs; });
        };
    };

}
