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
          codex.settings = {
            model = "o4-mini";
            approval_policy = "unless-allow-listed";
            developer_instructions = "Be concise";
            sandbox_mode = "platform-default";
          };

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
