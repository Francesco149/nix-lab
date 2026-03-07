{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nut = {
      url = "github:Francesco149/nix-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "nut/flake-parts";
      inputs.systems.follows = "deploy-rs/utils/systems";
    };
  };

  outputs =
    { self, nut, ... }@inputs:

    nut.lib.mf {
      inherit self inputs;
      dir = ./.;
      hosts = {
        code = {
          modules = [
            ./modules/docker.nix
            ./modules/nix.nix
          ];

          hmModules.root = [
            ./modules/hm/git.nix
            ./modules/hm/misc.nix

            (import ./modules/hm/nixvim.nix {
              inherit inputs;
              imports = [ ./lib/nixvim-ssh.nix ];
            })
          ];
        };
      };

      modules = [
        ./modules/system.nix
        ./modules/tailscale.nix
        ./modules/ssh.nix
      ];

      perSystem =
        { pkgs, ... }:
        {
          devShells.default = nut.lib.mkDevShell {
            inherit pkgs;
            shell = import ./lib/devShell.nix { inherit pkgs; };
          };
        };
    };

}
