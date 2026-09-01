#!/usr/bin/env zsh

local plugin_dir init_file os_init_file
plugin_dir=${0:A:h}
os_init_file="$plugin_dir/os/init.zsh"

[[ -r "$os_init_file" ]] && source "$os_init_file"

for init_file in "$plugin_dir"/*/init.zsh; do
  [[ -r "$init_file" ]] || continue
  [[ "$init_file" == "$os_init_file" ]] && continue
  source "$init_file"
done

unset plugin_dir init_file os_init_file
