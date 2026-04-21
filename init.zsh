#!/usr/bin/env zsh

local plugin_dir init_file
plugin_dir=${0:A:h}

for init_file in "$plugin_dir"/*/init.zsh; do
  [[ -r "$init_file" ]] || continue
  source "$init_file"
done

unset plugin_dir init_file
