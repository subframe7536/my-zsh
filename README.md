# my-zsh

Custom zsh helpers packaged as a single [zimfw](https://zimfw.sh/) plugin.

## Install

Add this module to `~/.zimrc`:

```zsh
zmodule subframe7536/my-zsh
```

Then install or update modules:

```zsh
zimfw install
```

## Included tools

- `kill-p`: fuzzy and direct process killer.
- `ni`: lightweight shell implementation of selected `@antfu/ni` commands.

Each tool is loaded automatically from its own `*/init.zsh` file when zimfw loads this module.
