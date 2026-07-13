{
  description = "codexnix integration test";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    codexnix.url = "path:/home/collin/projects/codexnix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      codexnix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ codexnix.flakeModules.default ];

      systems = [ "x86_64-linux" ];

      perSystem =
        { config, pkgs, ... }:
        {
          codex.trustProjectRoot = true;
          codex.settings = {
            model = "o4-mini";
            approval_policy = "unless-allow-listed";
            developer_instructions = "Be concise";
            sandbox_mode = "platform-default";
          };

          # Run the shell hook inside a throwaway git repo and assert it produces
          # a writable config.toml carrying both the generated settings and a
          # trust entry keyed on the resolved repo root.
          checks.trust-shellhook = pkgs.runCommand "check-trust-shellhook" { nativeBuildInputs = [ pkgs.git ]; } ''
            export HOME="$TMPDIR"
            mkdir -p "$TMPDIR/repo"
            cd "$TMPDIR/repo"
            git init -q

            ${config.codex.shellHook}

            echo "=== Materialized config.toml ==="
            cat "$CODEX_HOME/config.toml"

            # A writable regular file, not a read-only store symlink.
            test -f "$CODEX_HOME/config.toml"
            test ! -L "$CODEX_HOME/config.toml"
            test -w "$CODEX_HOME/config.toml"

            # Generated settings survive alongside the trust entry.
            grep -q 'model = "o4-mini"' "$CODEX_HOME/config.toml"
            grep -q 'trust_level = "trusted"' "$CODEX_HOME/config.toml"
            grep -qF "[projects.\"$(git rev-parse --show-toplevel)\"]" "$CODEX_HOME/config.toml"

            # Idempotent: a second entry leaves the file unchanged.
            cp "$CODEX_HOME/config.toml" "$TMPDIR/first"
            ${config.codex.shellHook}
            diff -q "$TMPDIR/first" "$CODEX_HOME/config.toml"

            echo "Trust shell hook checks passed"
            touch $out
          '';

          checks.settings-content = pkgs.runCommand "check-settings" { } ''
            echo "=== Generated config.toml ==="
            cat ${config.codex.settingsFile}

            # Verify expected keys
            grep -q 'model = "o4-mini"' ${config.codex.settingsFile}
            grep -q 'approval_policy = "unless-allow-listed"' ${config.codex.settingsFile}
            grep -q 'developer_instructions = "Be concise"' ${config.codex.settingsFile}
            grep -q 'sandbox_mode = "platform-default"' ${config.codex.settingsFile}

            # Verify absent keys (unset options should not appear)
            ! grep -q 'log_dir' ${config.codex.settingsFile}
            ! grep -q 'profile' ${config.codex.settingsFile}

            echo "All checks passed"
            touch $out
          '';
        };
    };
}
