{
  nixpkgs.overlays = [
    (_final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_pythonFinal: pythonPrev: {
          # inline-snapshot 0.32.5's documentation snapshots assume Black 25
          # formatting and fail with Black 26.5.1. Keep the functional test
          # suite while nixpkgs/upstream catches up.
          inline-snapshot = pythonPrev.inline-snapshot.overridePythonAttrs (old: {
            disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [ "tests/test_docs.py" ];
          });
        })
      ];
    })
  ];

  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
    ];

    # Avoid the channels.nixos.org flake-registry refresh on every invocation:
    # it has repeatedly 503'd/timeout and hangs nix for minutes. With an empty
    # registry, shorthand flakes (nixpkgs#...) resolve via /etc/nix/registry.json
    # (NixOS pins nixpkgs to this flake's input) — deterministic and offline.
    # GitHub refs still need a token: `refresh-nix-tokens` in dev.fish writes
    # extra-access-tokens to ~/.config/nix/nix.conf (kept out of the repo/store).
    flake-registry = "";

    substituters = [
      "https://nix-community.cachix.org"
      "https://cache.nixos-cuda.org"
      "https://cache.numtide.com"
    ];

    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];

    trusted-users = [
      "root"
      "headpats"
    ];
  };
}
