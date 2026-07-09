{
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;

  generatedOptions = import ../generated/options.nix { inherit lib; };

  # Recursively strip null leaves and collapse empty attrsets to null.
  # Skips derivations (which are attrsets with a _type field).
  removeNulls =
    val:
    if builtins.isAttrs val && !(val ? _type) then
      let
        cleaned = builtins.mapAttrs (_: removeNulls) val;
        filtered = lib.filterAttrs (_: v: v != null) cleaned;
      in
      if filtered == { } then null else filtered
    else if builtins.isList val then
      map removeNulls val
    else
      val;
in
{
  options = {
    perSystem = mkPerSystemOption (
      { config, pkgs, ... }:
      let
        cfg = config.codex;
        tomlFormat = pkgs.formats.toml { };
        cleaned = removeNulls cfg.settings;
        cleanSettings = if cleaned == null then { } else cleaned;
      in
      {
        options.codex = {
          settings = mkOption {
            type = types.submodule {
              options = generatedOptions;
            };
            default = { };
            description = "OpenAI Codex CLI settings. Values are rendered to .codex/config.toml";
          };

          settingsFile = mkOption {
            type = types.package;
            readOnly = true;
            description = "Derivation producing the Codex config.toml file.";
          };

          addGcRoot = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to add `.codex/config.toml` as an indirect garbage collector root.
              When false, the shell hook creates a symlink to the generated file instead.
            '';
          };

          shellHook = mkOption {
            type = types.str;
            readOnly = true;
            description = "Shell hook that writes .codex/config.toml into the project root.";
          };
        };

        config.codex = {
          settingsFile = tomlFormat.generate "config.toml" cleanSettings;

          shellHook = ''
            # Anchor to the repository root so the config lands in the same place
            # regardless of which subdirectory the dev shell is entered from.
            codexHome="$(git rev-parse --show-toplevel)/.codex"
            mkdir -p "$codexHome"
            if ! diff -q <(cat "$codexHome/config.toml" 2>/dev/null) ${cfg.settingsFile} &>/dev/null; then
              ${
                if cfg.addGcRoot then
                  ''nix-store --add-root "$codexHome/config.toml" --indirect --realise ${cfg.settingsFile}''
                else
                  ''ln -sf ${cfg.settingsFile} "$codexHome/config.toml"''
              }
              echo "codexnix: updated .codex/config.toml"
            fi

            # The codex CLI resolves its config from $CODEX_HOME (default ~/.codex);
            # point it at the project's .codex so the generated config is the one used.
            export CODEX_HOME="$codexHome"
          '';
        };
      }
    );
  };
}
