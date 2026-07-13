# codexnix

A [flake-parts](https://github.com/hercules-ci/flake-parts) module for managing [OpenAI Codex CLI](https://github.com/openai/codex) settings as typed Nix options. Declare your `.codex/config.toml` in Nix and get type checking, enums, descriptions, and per-project configuration for free.

The Nix options are auto-generated from Codex's [JSON Schema](https://raw.githubusercontent.com/openai/codex/main/codex-rs/core/config.schema.json) using [jsonschema2nix](https://github.com/collinarnett/jsonschema2nix), so they stay in sync with upstream as the schema evolves.

## Usage

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    codexnix.url = "github:collinarnett/codexnix";
  };

  outputs = inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.codexnix.flakeModules.default ];

      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { config, pkgs, ... }: {
        codex.settings = {
          model = "o4-mini";
          approval_policy = "unless-allow-listed";
          sandbox_mode = "platform-default";
          developer_instructions = "Be concise and direct.";
        };

        devShells.default = pkgs.mkShell {
          shellHook = config.codex.shellHook;
        };
      };
    };
}
```

Entering the devShell writes `.codex/config.toml` with only the keys you set:

```toml
approval_policy = "unless-allow-listed"
developer_instructions = "Be concise and direct."
model = "o4-mini"
sandbox_mode = "platform-default"
```

## Module outputs

| Option | Type | Description |
|---|---|---|
| `codex.settings` | submodule | All Codex CLI settings as typed Nix options |
| `codex.settingsFile` | package (read-only) | Derivation producing `config.toml` |
| `codex.addGcRoot` | bool (default `false`) | Pin `.codex/config.toml` as an indirect GC root instead of a plain symlink |
| `codex.trustProjectRoot` | bool (default `false`) | Mark the checkout as a trusted Codex project (see below) |
| `codex.shellHook` | string (read-only) | Shell snippet that writes `.codex/config.toml` |

## Trusting the project root

Codex records per-project trust by writing a `[projects."<root>"]` table into
`$CODEX_HOME/config.toml` at runtime. Because codexnix points `CODEX_HOME` at the
repo's `.codex` and links `config.toml` to a read-only store path, that write
fails with `failed to set trust setting`.

Set `codex.trustProjectRoot = true` to have the shell hook materialize a writable
`config.toml` (the generated settings plus a trust entry for the repo root). The
root is resolved at shell-entry via `git rev-parse`, so nothing checkout-specific
is committed and each clone trusts its own location:

```nix
perSystem = { config, ... }: {
  codex.trustProjectRoot = true;
  codex.settings.approval_policy = "on-request";
};
```

## Regenerating options

When Codex's schema changes upstream, regenerate `generated/options.nix`:

```bash
nix run .#generate > generated/options.nix
```

## License

MIT
