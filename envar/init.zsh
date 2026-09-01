#!/usr/bin/env zsh

# Global dotenv environment manager. All implementation is intentionally kept
# in this file so it can be sourced directly or through the plugin loader.

if [[ -z ${functions[os]-} ]]; then
  typeset _envar_os_init=${${(%):-%N}:A:h}/../os/init.zsh
  [[ -r $_envar_os_init ]] && source "$_envar_os_init"
  unset _envar_os_init
fi

typeset -g _ENVAR_FILE=${ENVAR_FILE:-${HOME}/.env.global}
typeset -ga _ENVAR_LOADED_KEYS=() _ENVAR_LOADED_PATHS=()
typeset -g _ENVAR_PLATFORM=$(os 2>/dev/null)
[[ -n $_ENVAR_PLATFORM ]] || _ENVAR_PLATFORM=unknown

_envar_err() {
  printf 'envar: %s\n' "$*" >&2
}
_envar_usage() {
  printf 'usage: envar %s\n' "$*" >&2
}
_envar_windows() {
  [[ $_ENVAR_PLATFORM == windows ]]
}
_envar_file() {
  print -r -- "${1:-${ENVAR_FILE:-${_ENVAR_FILE}}}"
}
_envar_valid_key() {
  [[ $1 =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]]
}

_envar_decode() {
  local value=$1
  typeset -g _ENVAR_EXPAND=1
  value=${value##[[:space:]]#}
  value=${value%%[[:space:]]#}
  if [[ $value == "'"*"'" && ${#value} -ge 2 ]]; then
    REPLY=${value[2,-2]}
    _ENVAR_EXPAND=0
  elif [[ $value == '"'*'"' && ${#value} -ge 2 ]]; then
    REPLY=${value[2,-2]}
    REPLY=${REPLY//\\\\/\\}
    REPLY=${REPLY//\\\"/\"}
  else
    [[ $value == *\#* ]] && value=${value%%\#*}
    REPLY=${value%%[[:space:]]#}
  fi
}

_envar_expand() {
  local value=$1 rest name replacement prefix
  local result=
  while [[ $value == *'{{'*'}}'* ]]; do
    prefix=${value%%'{{'*}
    rest=${value#*'{{'}
    if [[ $rest =~ '^([A-Za-z_][A-Za-z0-9_]*)(}}.*)$' ]]; then
      name=$match[1]
      value=${match[2]#'}}'}
    else
      result+="${prefix}{{"
      value=$rest
      continue
    fi
    if [[ -n ${_ENVAR_RAW_VALUES[$name]+x} ]]; then
      replacement=${_ENVAR_RAW_VALUES[$name]}
    elif [[ -n ${parameters[$name]+x} ]]; then
      replacement=${(P)name}
    else
      replacement=
    fi
    result+="$prefix$replacement"
  done
  REPLY="$result$value"
}

_envar_parse() {
  local file=$1 line key raw value n=0
  [[ -r $file ]] || { _envar_err "file not found: $file"; return 1; }
  typeset -gA _ENVAR_VALUES=()
  typeset -gA _ENVAR_RAW_VALUES=()
  typeset -gA _ENVAR_KEY_EXPAND=()
  typeset -ga _ENVAR_KEYS=() _ENVAR_PATH_VALUES=()
  typeset -ga _ENVAR_RAW_PATH_VALUES=() _ENVAR_PATH_EXPAND=()
  while IFS= read -r line || [[ -n $line ]]; do
    (( n++ ))
    [[ -z ${line##[[:space:]]#} || ${line##[[:space:]]#} == \#* ]] && continue
    if [[ $line =~ '^[[:space:]]*([^=[:space:]]+)[[:space:]]*=(.*)$' ]]; then
      key=$match[1]
      raw=$match[2]
    else
      _envar_err "invalid dotenv syntax at $file:$n"
      return 2
    fi
    if ! _envar_valid_key "$key"; then
      _envar_err "invalid variable name '$key' at $file:$n"
      return 2
    fi
    _envar_decode "$raw"
    value=$REPLY
    if [[ $key == PATH ]]; then
      _ENVAR_RAW_PATH_VALUES+=($value)
      _ENVAR_PATH_EXPAND+=($_ENVAR_EXPAND)
    else
      [[ -n ${_ENVAR_VALUES[$key]+x} ]] || _ENVAR_KEYS+=($key)
      _ENVAR_RAW_VALUES[$key]=$value
      _ENVAR_KEY_EXPAND[$key]=$_ENVAR_EXPAND
      _ENVAR_VALUES[$key]=$value
    fi
  done < "$file"

  _ENVAR_PATH_VALUES=()
  local index expanded
  for index in {1..${#_ENVAR_RAW_PATH_VALUES}}; do
    expanded=${_ENVAR_RAW_PATH_VALUES[index]}
    [[ ${_ENVAR_PATH_EXPAND[index]} == 1 ]] && { _envar_expand "$expanded"; expanded=$REPLY; }
    _ENVAR_PATH_VALUES+=($expanded)
  done
  for key in "${_ENVAR_KEYS[@]}"; do
    expanded=${_ENVAR_RAW_VALUES[$key]}
    [[ ${_ENVAR_KEY_EXPAND[$key]} == 1 ]] && {
      _envar_expand "$expanded"
      expanded=$REPLY
    }
    _ENVAR_VALUES[$key]=$expanded
  done
}

_envar_path_append() {
  local item=$1
  [[ -n $item ]] || return 0
  if [[ -n $PATH ]]; then
    PATH+=":$item"
  else
    PATH=$item
  fi
  export PATH
  _ENVAR_LOADED_PATHS+=($item)
}
_envar_path_remove_current() {
  local item=$1 part
  local -a out=()
  for part in ${(s.:.)PATH}; do
    [[ $part == $item ]] || out+=($part)
  done
  PATH=${(j.:.)out}
  export PATH
}

_envar_sync_windows() {
  _envar_windows || return 0
  local key=$1 value=${2-} mode=${3-set}
  command -v powershell.exe >/dev/null 2>&1 || { _envar_err 'powershell.exe not found; persistence skipped'; return 1; }
  case $mode in
    unset)
      powershell.exe -NoProfile -Command '& { param($n); [Environment]::SetEnvironmentVariable($n,$null,"User") }' "$key"
      ;;
    path-add)
      powershell.exe -NoProfile -Command '& { param($p); $v=[Environment]::GetEnvironmentVariable("Path","User"); $a=@(); if($v){$a=$v -split ";"}; if($a -notcontains $p){$a+= $p}; [Environment]::SetEnvironmentVariable("Path",($a -join ";"),"User") }' "$value"
      ;;
    path-remove)
      powershell.exe -NoProfile -Command '& { param($p); $v=[Environment]::GetEnvironmentVariable("Path","User"); $a=@(); if($v){$a=@($v -split ";" | ? {$_ -ne $p})}; [Environment]::SetEnvironmentVariable("Path",($a -join ";"),"User") }' "$value"
      ;;
    *)
      powershell.exe -NoProfile -Command '& { param($n,$v); [Environment]::SetEnvironmentVariable($n,$v,"User") }' "$key" "$value"
      ;;
  esac
}

_envar_unload() {
  local key item
  for key in "${_ENVAR_LOADED_KEYS[@]}"; do unset "$key"; done
  for item in "${_ENVAR_LOADED_PATHS[@]}"; do
    _envar_path_remove_current "$item"
  done
  _ENVAR_LOADED_KEYS=()
  _ENVAR_LOADED_PATHS=()
}
_envar_load() {
  local file=$1 key value load_status=0
  _envar_parse "$file" || return $?
  _envar_unload
  for key in "${_ENVAR_KEYS[@]}"; do
    value=${_ENVAR_VALUES[$key]}
    export "$key=$value"
    _ENVAR_LOADED_KEYS+=($key)
    _envar_sync_windows "$key" "$value" || load_status=1
  done
  for value in "${_ENVAR_PATH_VALUES[@]}"; do
    _envar_path_append "$value"
    _envar_sync_windows PATH "$value" path-add || load_status=1
  done
  _ENVAR_FILE=$file
  return $load_status
}

_envar_write_lines() {
  local file=$1 tmp=${file}.envar.$$
  print -rl -- "${_ENVAR_EDIT_LINES[@]}" >| "$tmp" || return 1
  mv -f -- "$tmp" "$file"
}
_envar_encode() {
  local value=$1
  if [[ $value == *[[:space:]\#\"\'\=]* || -z $value ]]; then
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    REPLY="\"$value\""
  else
    REPLY=$value
  fi
}
_envar_edit_set() {
  local file=$1 target=$2 value=$3 line idx=0 last=0
  [[ -f $file ]] || print -r -- '' >| "$file"
  _ENVAR_EDIT_LINES=()
  while IFS= read -r line || [[ -n $line ]]; do
    _ENVAR_EDIT_LINES+=($line)
  done < "$file"
  for line in "${_ENVAR_EDIT_LINES[@]}"; do
    (( idx++ ))
    if [[ $line =~ '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=' ]] && [[ $match[1] == $target ]]; then
      last=$idx
    fi
  done
  _envar_encode "$value"
  if (( last )); then
    _ENVAR_EDIT_LINES[last]="$target=$REPLY"
  else
    _ENVAR_EDIT_LINES+=("$target=$REPLY")
  fi
  _envar_write_lines "$file"
}
_envar_edit_unset() {
  local file=$1 target=$2 line
  [[ -f $file ]] || return 0
  _ENVAR_EDIT_LINES=()
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=' ]] && [[ $match[1] == $target ]]; then
      continue
    fi
    _ENVAR_EDIT_LINES+=($line)
  done < "$file"
  _envar_write_lines "$file"
}
_envar_path_edit() {
  local file=$1 action=$2 value=$3 line decoded
  [[ -f $file ]] || print -r -- '' >| "$file"
  _ENVAR_EDIT_LINES=()
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ '^[[:space:]]*PATH[[:space:]]*=(.*)$' ]]; then
      _envar_decode "$match[1]"
      decoded=$REPLY
      [[ $action == remove && $decoded == $value ]] && continue
    fi
    _ENVAR_EDIT_LINES+=($line)
  done < "$file"
  if [[ $action == add ]]; then
    _envar_encode "$value"
    _ENVAR_EDIT_LINES+=("PATH=$REPLY")
  fi
  _envar_write_lines "$file"
}

envar() {
  local cmd=${1:-help}
  local file key value sub
  if (( $# > 0 )); then
    shift
  fi
  case $cmd in
    help|-h|--help)
      cat <<'EOF'
envar - load global dotenv variables from $HOME/.env.global

Usage: envar <load|unload|reload|list|show|edit|set|unset|path|help>
  load [file]       Load variables (default: $HOME/.env.global)
  unload            Unset variables loaded by envar
  reload [file]     Unload then load variables
  list              List loaded variables and PATH entries
  show [file]       Print dotenv file
  edit [file]       Edit file ($EDITOR, notepad.exe, or vi)
  set KEY VALUE     Set a variable; use {{NAME}} for load-time expansion
  unset KEY         Remove a variable
  path add DIR      Append PATH entry; path remove|rm DIR; path list|ls
EOF
      ;;
    load|reload)
      if (( $# > 1 )); then
        _envar_usage "$cmd [file]"
        return 2
      fi
      file=$(_envar_file "${1-}")
      if [[ $cmd == reload ]]; then
        _envar_unload
      fi
      _envar_load "$file"
      ;;
    unload)
      if (( $# != 0 )); then
        _envar_usage unload
        return 2
      fi
      _envar_unload
      ;;
    list)
      if (( $# != 0 )); then
        _envar_usage list
        return 2
      fi
      file=$(_envar_file)
      _envar_parse "$file" || return $?
      for key in "${_ENVAR_KEYS[@]}"; do
        printf '%s=%s\n' "$key" "${_ENVAR_VALUES[$key]}"
      done
      if (( ${#_ENVAR_PATH_VALUES[@]} > 0 )); then
        print PATH
        for value in "${_ENVAR_PATH_VALUES[@]}"; do
          printf '%s\n' "- $value"
        done
      fi
      ;;
    show)
      if (( $# > 1 )); then
        _envar_usage 'show [file]'
        return 2
      fi
      file=$(_envar_file "${1-}")
      if [[ ! -r $file ]]; then
        _envar_err "file not found: $file"
        return 1
      fi
      cat -- "$file"
      ;;
    edit)
      if (( $# > 1 )); then
        _envar_usage 'edit [file]'
        return 2
      fi
      file=$(_envar_file "${1-}")
      [[ -e $file ]] || print -r -- '' >| "$file"
      local editor_status=0
      ${EDITOR:-$(_envar_windows && print notepad.exe || print vi)} "$file" || editor_status=$?
      if (( editor_status != 0 )); then
        return $editor_status
      fi
      _envar_load "$file"
      ;;
    set)
      if (( $# != 2 )); then
        _envar_usage 'set KEY VALUE'
        return 2
      fi
      key=$1
      value=$2
      if ! _envar_valid_key "$key"; then
        _envar_err "invalid variable name: $key"
        return 2
      fi
      if [[ $key == PATH ]]; then
        _envar_err 'use `envar path` to manage PATH'
        return 2
      fi
      file=$(_envar_file)
      _envar_edit_set "$file" "$key" "$value" || return 1
      export "$key=$value"
      _ENVAR_LOADED_KEYS+=("$key")
      _envar_sync_windows "$key" "$value"
      ;;
    unset)
      if (( $# != 1 )); then
        _envar_usage 'unset KEY'
        return 2
      fi
      key=$1
      if ! _envar_valid_key "$key"; then
        _envar_err "invalid variable name: $key"
        return 2
      fi
      if [[ $key == PATH ]]; then
        _envar_err 'use `envar path` to manage PATH'
        return 2
      fi
      file=$(_envar_file)
      _envar_edit_unset "$file" "$key" || return 1
      unset "$key"
      _envar_sync_windows "$key" '' unset
      ;;
    path)
      sub=${1:-list}
      if (( $# > 0 )); then
        shift
      fi
      case $sub in
        add)
          if (( $# != 1 )); then
            _envar_usage 'path add DIR'
            return 2
          fi
          file=$(_envar_file)
          _envar_path_edit "$file" add "$1" || return 1
          _envar_path_append "$1"
          _envar_sync_windows PATH "$1" path-add
          ;;
        remove|rm)
          if (( $# != 1 )); then
            _envar_usage 'path remove DIR'
            return 2
          fi
          file=$(_envar_file)
          _envar_path_edit "$file" remove "$1" || return 1
          _envar_path_remove_current "$1"
          _envar_sync_windows PATH "$1" path-remove
          ;;
        list|ls)
          if (( $# != 0 )); then
            _envar_usage 'path list'
            return 2
          fi
          file=$(_envar_file)
          _envar_parse "$file" || return $?
          print -rl -- "${_ENVAR_PATH_VALUES[@]}"
          ;;
        *)
          _envar_err "unknown path command: $sub"
          return 2
          ;;
      esac
      ;;
    *)
      _envar_err "unknown command: $cmd"
      return 2
      ;;
  esac
}
