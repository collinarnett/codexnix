{
  description = "Codexnix — Nix-native OpenAI Codex CLI settings management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    jsonschema2nix.url = "github:collinarnett/jsonschema2nix";
    codex-src = {
      url = "github:openai/codex";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      jsonschema2nix,
      codex-src,
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
          schemaFile = codex-src + "/codex-rs/core/config.schema.json";
          j2n = jsonschema2nix.packages.${system}.default;
        in
        {
          apps.generate = {
            type = "app";
            program =
              let
                script = pkgs.writeShellApplication {
                  name = "codexnix-generate";
                  runtimeInputs = [ j2n pkgs.glibcLocales ];
                  text = ''
                    export LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive
                    export LANG=C.UTF-8
                    export LC_ALL=C.UTF-8
                    jsonschema2nix --skip "\$schema" < ${schemaFile}
                  '';
                };
              in
              "${script}/bin/codexnix-generate";
          };

          checks.generated-up-to-date = pkgs.runCommand "check-generated" { nativeBuildInputs = [ j2n pkgs.glibcLocales ]; } ''
            export LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive
            export LANG=C.UTF-8
            export LC_ALL=C.UTF-8
            expected=$(jsonschema2nix --skip "\$schema" < ${schemaFile})
            diff <(echo "$expected") ${./generated/options.nix}
            touch $out
          '';
        };
    };
}
