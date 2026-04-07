{
  description = "Codexnix — Nix-native OpenAI Codex CLI settings management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    jsonschema2nix.url = "github:collinarnett/jsonschema2nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      jsonschema2nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake.flakeModules.default = ./modules/codex-settings.nix;

      perSystem =
        { pkgs, system, ... }:
        let
          schemaUrl = "https://raw.githubusercontent.com/openai/codex/main/codex-rs/core/config.schema.json";
          j2n = jsonschema2nix.packages.${system}.default;
        in
        {
          apps.generate = {
            type = "app";
            program =
              let
                script = pkgs.writeShellApplication {
                  name = "codexnix-generate";
                  runtimeInputs = with pkgs; [
                    curl
                    j2n
                  ];
                  text = ''
                    curl -sL "${schemaUrl}" | jsonschema2nix --skip '$schema'
                  '';
                };
              in
              "${script}/bin/codexnix-generate";
          };

          checks.generated-up-to-date = pkgs.runCommand "check-generated" { nativeBuildInputs = [ pkgs.curl j2n ]; } ''
            expected=$(curl -sL "${schemaUrl}" | jsonschema2nix --skip '$schema')
            diff <(echo "$expected") ${./generated/options.nix}
            touch $out
          '';
        };
    };
}
