# ni-sh

Minimal shell implementation of selected `ni` commands:

- `ni`
- `nci`
- `nr`
- `nup`
- `nlx`
- `NI_DRY_RUN` env var (dry-run mode for all commands)

Core logic is POSIX `sh` compatible in `_ni_core.sh`.
Command entry points are provided as zsh functions via `ni.zsh`.

## Usage

```sh
ni
ni axios
NI_DRY_RUN=1 ni axios
NI_DRY_RUN=1 ni -D axios

nci
NI_DRY_RUN=1 nci

nr dev
NI_DRY_RUN=1 nr build
nr

nup
NI_DRY_RUN=1 nup

nlx eslint --version
NI_DRY_RUN=1 nlx eslint --version
```

Set `NI_DRY_RUN=1` (or `true/yes/on`) to print commands without executing them.

## Package manager detection

Lookup starts from current directory and walks upward.

Priority:

1. `pnpm-lock.yaml` -> `pnpm`
2. `bun.lockb` / `bun.lock` -> `bun`
3. `yarn.lock` -> `yarn`
4. `package-lock.json` / `npm-shrinkwrap.json` -> `npm`
5. no lockfile -> error

## Command mapping

### `ni`

- no args: install dependencies
- with args: add/install packages
- requires a detected lockfile; no lockfile -> error

### `nci`

- frozen/clean install command per package manager

### `nr`

- with args: run script directly
- no args: interactive script picker from `package.json` (`jq` + `fzf` required)

### `nup`

- `pnpm` -> `pnpm update -i`
- `bun` -> `bun update -i`
- `yarn` -> `yarn upgrade-interactive` (Yarn 1) / `yarn up -i` (Yarn Berry)
- `npm` -> `npm upgrade`

### `nlx`

- `npm` -> `npx`
- `yarn` -> `yarn dlx`
- `pnpm` -> `pnpx`
- `bun` -> `bunx`
