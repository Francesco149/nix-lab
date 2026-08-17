{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  ompConfigYml = pkgs.writeText "omp-config.yml" (builtins.readFile ./omp-config.yml);
  ompModelsYml = pkgs.writeText "omp-models.yml" (builtins.readFile ./omp-models.yml);
in
{
  home.packages = [
    # oh-my-pi (omp) — the coding-agent harness sentdex concluded is optimal for
    # DeepSeek-V4-Flash. omp-nix ships the prebuilt release binary wrapped for
    # NixOS (ld-linux interpreter + BUN_SELF_EXE), so nothing builds from source.
    # wslop-only for now; see WORKDOC if it should spread to other interactive hosts.
    inputs.omp-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # config.yml + models.yml must be REAL writable files, not store symlinks:
  # omp's settings flush writes a temp file next to the symlink target and
  # renames, so a home-manager store symlink fails with EROFS. That breaks the
  # first-run wizard (settings.set("setupVersion") can't persist) and /settings.
  # omp's own nix/home-manager.nix documents the same limitation. We copy over
  # the symlink every activation: declarative source of truth, omp edits+revert
  # on the next switch (same semantics as omp's official HM module).
  home.activation.ompConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.omp/agent"
    run cp -fT ${ompConfigYml} "$HOME/.omp/agent/config.yml"
    run chmod 600 "$HOME/.omp/agent/config.yml"
    run cp -fT ${ompModelsYml} "$HOME/.omp/agent/models.yml"
    run chmod 600 "$HOME/.omp/agent/models.yml"
    run cp -fT ${./APPEND_SYSTEM.md} "$HOME/.omp/agent/APPEND_SYSTEM.md"
    run chmod 600 "$HOME/.omp/agent/APPEND_SYSTEM.md"
    run mkdir -p "$HOME/.omp/agent/skills"
    run cp -rf ${./skills}/. "$HOME/.omp/agent/skills/"
  '';

  # gotcha comment that travels with the files. API key lives OUTSIDE nix in
  # ~/.omp/agent/.env (DEEPSEEK_API_KEY=...), which omp loads eagerly, so the
  # key never lands in the store. If the file is missing, run:
  #   echo 'DEEPSEEK_API_KEY=sk-...' > ~/.omp/agent/.env && chmod 600 ~/.omp/agent/.env
  home.activation.ompEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run touch "$HOME/.omp/agent/.env"
    run chmod 600 "$HOME/.omp/agent/.env"
  '';
}