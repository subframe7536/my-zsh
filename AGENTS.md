# Repository Guidelines

## Project Structure & Module Organization

This repository is a [zimfw](https://zimfw.sh/) plugin containing small shell utilities. The root [`init.zsh`](init.zsh) is the plugin entry point: it sources every `*/init.zsh` module automatically. Keep each user-facing command in its own directory, for example `kill-p/init.zsh`, `ni/init.zsh`, or `ghdns/init.zsh`. Put module-specific usage notes beside the implementation (as `ni/README.md` does).

## Development and Validation Commands

There is no build system or dependency installation step; these are sourced shell scripts.

- `zsh -n init.zsh` checks the plugin entry point syntax without executing code. Add every changed Zsh module to this command.
- `zsh -f` starts a clean shell for manual smoke tests. Source the module, e.g. `source "$PWD/ni/init.zsh"; ni --help`. Ensure required tools such as `awk` are available on `PATH`.
- Use safe modes when available: `ghdns --dry-run` must be used before testing an actual hosts-file update.

## Coding Style & Naming Conventions

Use English for code, comments, help text, and documentation. Preserve the interpreter declared by each shebang: use portable `sh` syntax in `#!/usr/bin/env sh` files and Zsh features only in Zsh modules. Indent with two spaces, quote variable expansions, and prefer `printf` over `echo` where output needs to be portable. Name public commands in kebab case (`kill-p`); prefix implementation helpers and temporary globals with the module name (`_ni_*`, `_kill_p_*`, `_envar_*`) to avoid collisions in the user’s interactive shell.

## Testing Guidelines

No automated test framework or coverage target is currently configured. Every behavior change needs syntax checks plus a focused manual test covering success, invalid input, and a missing required command. Do not run privileged or destructive paths during normal validation; exercise `--help` and dry-run paths instead. Add regression scripts or tests with a new module when its parsing or platform logic becomes non-trivial.
