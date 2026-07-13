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

          trustProjectRoot = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to mark the detected repository root as a trusted Codex project.

              Codex records per-project trust by writing a `[projects."<root>"]`
              table into `$CODEX_HOME/config.toml` at runtime. A read-only store
              symlink cannot hold that write, so trusting a folder fails with
              "failed to set trust setting". When this option is enabled the shell
              hook instead materializes a writable `config.toml` — the generated
              settings plus a trust entry keyed on the repository root — so Codex
              starts trusted without prompting.

              The root is resolved at shell-entry time via `git rev-parse`, so no
              absolute path is baked into the committed configuration; each checkout
              trusts its own location. Takes precedence over `addGcRoot`.
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

          shellHook =
            let
              # When trust is requested the config must be writable so Codex can
              # persist future trust decisions, so it is copied rather than
              # symlinked into the store. Otherwise link (or gc-root) the
              # immutable generated file directly.
              writeConfig =
                if cfg.trustProjectRoot then
                  ''
                    # Compose the generated settings with a trust entry for this
                    # checkout, resolved at runtime so no path is committed.
                    {
                      cat ${cfg.settingsFile}
                      printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$codexRoot"
                    } > "$codexHome/config.toml.tmp"
                    if ! diff -q "$codexHome/config.toml.tmp" "$codexHome/config.toml" &>/dev/null; then
                      mv -f "$codexHome/config.toml.tmp" "$codexHome/config.toml"
                      echo "codexnix: updated .codex/config.toml"
                    else
                      rm -f "$codexHome/config.toml.tmp"
                    fi
                  ''
                else
                  ''
                    if ! diff -q <(cat "$codexHome/config.toml" 2>/dev/null) ${cfg.settingsFile} &>/dev/null; then
                      ${
                        if cfg.addGcRoot then
                          ''nix-store --add-root "$codexHome/config.toml" --indirect --realise ${cfg.settingsFile}''
                        else
                          ''ln -sf ${cfg.settingsFile} "$codexHome/config.toml"''
                      }
                      echo "codexnix: updated .codex/config.toml"
                    fi
                  '';
            in
            lib.warnIf (cfg.trustProjectRoot && cfg.addGcRoot)
              "codexnix: trustProjectRoot needs a writable config, so it overrides addGcRoot (config.toml is copied, not gc-rooted)."
              ''
                # Anchor to the repository root so the config lands in the same place
                # regardless of which subdirectory the dev shell is entered from.
                codexRoot="$(git rev-parse --show-toplevel)"
                codexHome="$codexRoot/.codex"
                mkdir -p "$codexHome"
                ${writeConfig}
                # The codex CLI resolves its config from $CODEX_HOME (default ~/.codex);
                # point it at the project's .codex so the generated config is the one used.
                export CODEX_HOME="$codexHome"
              '';
        };
      }
    );
  };
}
