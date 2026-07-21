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
