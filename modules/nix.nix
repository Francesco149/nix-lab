{
  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
    ];

    eval-cache = true;
    keep-derivations = true;

    substituters = [
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
