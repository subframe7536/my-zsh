#!/usr/bin/env sh

_ni_err() {
  printf '%s\n' "$*" >&2
}

_ni_quote_arg() {
  printf '%s' "$1"
}

_ni_print_cmd() {
  _ni_line=''
  for _ni_a in "$@"; do
    _ni_q=$(_ni_quote_arg "$_ni_a")
    if [ -z "$_ni_line" ]; then
      _ni_line=$_ni_q
    else
      _ni_line="$_ni_line $_ni_q"
    fi
  done
  printf '[dry-run] %s\n' "$_ni_line"
}

_ni_parse_args() {
  NI_ARGC=$#
  case "${NI_DRY_RUN-}" in
    1|true|TRUE|yes|YES|on|ON) NI_DRY_RUN=1 ;;
    *) NI_DRY_RUN=0 ;;
  esac
}

_ni_require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    _ni_err "Error: command not found: $1"
    return 127
  fi
}

_ni_run() {
  [ $# -gt 0 ] || return 0
  if [ "$NI_DRY_RUN" = '1' ]; then
    _ni_print_cmd "$@"
    return 0
  fi
  _ni_require_cmd "$1" || return $?
  "$@"
}

_ni_find_project_root() {
  _ni_d=$PWD
  while :; do
    if [ -f "$_ni_d/package.json" ]; then
      printf '%s\n' "$_ni_d"
      return 0
    fi
    if [ "$_ni_d" = '/' ]; then
      break
    fi
    _ni_n=$(dirname "$_ni_d")
    if [ "$_ni_n" = "$_ni_d" ]; then
      break
    fi
    _ni_d=$_ni_n
  done
  return 1
}

_NI_HAS_NUB=""
_ni_has_nub() {
  if [ -z "$_NI_HAS_NUB" ]; then
    if command -v nub >/dev/null 2>&1; then
      _NI_HAS_NUB=1
    else
      _NI_HAS_NUB=0
    fi
  fi
  [ "$_NI_HAS_NUB" = 1 ]
}

_ni_detect_pm() {
  _ni_d=$PWD
  while :; do
    if [ -f "$_ni_d/pnpm-lock.yaml" ]; then
      printf 'pnpm\n'
      return 0
    fi
    if [ -f "$_ni_d/nub.lock" ]; then
      printf 'nub\n'
      return 0
    fi
    if [ -f "$_ni_d/bun.lockb" ] || [ -f "$_ni_d/bun.lock" ]; then
      printf 'bun\n'
      return 0
    fi
    if [ -f "$_ni_d/yarn.lock" ]; then
      printf 'yarn\n'
      return 0
    fi
    if [ -f "$_ni_d/package-lock.json" ] || [ -f "$_ni_d/npm-shrinkwrap.json" ]; then
      printf 'npm\n'
      return 0
    fi
    if [ "$_ni_d" = '/' ]; then
      break
    fi
    _ni_n=$(dirname "$_ni_d")
    if [ "$_ni_n" = "$_ni_d" ]; then
      break
    fi
    _ni_d=$_ni_n
  done
  return 1
}

_ni_resolve_pm() {
  _ni_detected=$(_ni_detect_pm)
  if [ -n "$_ni_detected" ]; then
    if [ "$_ni_detected" = "yarn" ]; then
      printf 'yarn\n'
      return 0
    fi
    if _ni_has_nub; then
      printf 'nub\n'
      return 0
    fi
    printf '%s\n' "$_ni_detected"
    return 0
  fi

  _ni_err 'No lockfile found. Select a package manager for this install:'
  _ni_selected=$(_ni_select_pm) || return $?

  if [ "$_ni_selected" = "yarn" ]; then
    printf 'yarn\n'
    return 0
  fi

  if _ni_has_nub; then
    printf 'nub\n'
    return 0
  fi

  printf '%s\n' "$_ni_selected"
  return 0
}

_ni_require_pm() {
  _ni_pm=$(_ni_detect_pm)
  if [ -n "$_ni_pm" ]; then
    if [ "$_ni_pm" = "yarn" ]; then
      printf 'yarn\n'
      return 0
    fi
    if _ni_has_nub; then
      printf 'nub\n'
      return 0
    fi
    printf '%s\n' "$_ni_pm"
    return 0
  fi
  _ni_err 'Error: no lockfile found, run `ni` first'
  return 1
}

_ni_select_pm() {
  _ni_require_cmd fzf || return $?

  _ni_pm_options=''
  for _ni_candidate in nub pnpm bun yarn npm; do
    if command -v "$_ni_candidate" >/dev/null 2>&1; then
      _ni_status_label='installed'
    else
      _ni_status_label='missing'
    fi

    _ni_option_line=$(printf '%-5s [%s]' "$_ni_candidate" "$_ni_status_label")
    if [ -z "$_ni_pm_options" ]; then
      _ni_pm_options=$_ni_option_line
    else
      _ni_pm_options=$(printf '%s\n%s' "$_ni_pm_options" "$_ni_option_line")
    fi
  done

  _ni_selected_pm=$(printf '%s\n' "$_ni_pm_options" | fzf --height=40% --layout=reverse --prompt='pm> ')
  _ni_status=$?
  if [ "$_ni_status" -ne 0 ]; then
    return "$_ni_status"
  fi

  _ni_selected_pm=$(printf '%s\n' "$_ni_selected_pm" | awk '{print $1}')
  if [ -z "$_ni_selected_pm" ]; then
    _ni_err 'Error: no package manager selected.'
    return 1
  fi

  printf '%s\n' "$_ni_selected_pm"
}

_ni_detect_yarn_cmd() {
  _ni_d=$PWD
  while :; do
    if [ -f "$_ni_d/.yarnrc.yml" ] || [ -d "$_ni_d/.yarn/releases" ]; then
      printf 'up -i\n'
      return 0
    fi
    if [ "$_ni_d" = '/' ]; then
      break
    fi
    _ni_n=$(dirname "$_ni_d")
    if [ "$_ni_n" = "$_ni_d" ]; then
      break
    fi
    _ni_d=$_ni_n
  done

  if command -v yarn >/dev/null 2>&1; then
    _ni_yarn_version=$(yarn --version 2>/dev/null)
    case "$_ni_yarn_version" in
      1.*) printf 'upgrade-interactive\n' ;;
      *) printf 'up -i\n' ;;
    esac
    return 0
  fi

  printf 'upgrade-interactive\n'
}

ni() {
  _ni_pm=$(_ni_resolve_pm) || return $?
  _ni_parse_args "$@"

  case "$_ni_pm" in
    nub) _ni_run nub i "$@" ;;
    pnpm) _ni_run pnpm i "$@" ;;
    yarn) _ni_run yarn i "$@" ;;
    bun) _ni_run bun i "$@" ;;
    npm) _ni_run npm install "$@" ;;
    *)
      _ni_err "Error: unsupported package manager: $_ni_pm"
      return 1
      ;;
  esac
}

nci() {
  _ni_pm=$(_ni_resolve_pm) || return $?
  _ni_parse_args "$@"

  case "$_ni_pm" in
    nub) _ni_run nub install --frozen-lockfile "$@" ;;
    pnpm) _ni_run pnpm install --frozen-lockfile "$@" ;;
    yarn) _ni_run yarn install --frozen-lockfile "$@" ;;
    bun) _ni_run bun ci "$@" ;;
    npm) _ni_run npm ci "$@" ;;
    *)
      _ni_err "Error: unsupported package manager: $_ni_pm"
      return 1
      ;;
  esac
}

nr() {
  _ni_pm=$(_ni_require_pm) || return $?
  _ni_parse_args "$@"

  if [ "$NI_ARGC" -gt 0 ]; then
    _ni_run "$_ni_pm" run "$@"
    return $?
  fi

  if [ "$NI_DRY_RUN" = '1' ]; then
    _ni_print_cmd "$_ni_pm" run
    return 0
  fi

  _ni_root=$(_ni_find_project_root) || {
    _ni_err 'Error: package.json not found.'
    return 1
  }

  _ni_require_cmd jq || return $?
  _ni_require_cmd fzf || return $?
  _ni_require_cmd column || return $?

  _ni_scripts=$(jq -r '
    if (.scripts|type) == "object" then
      .scripts | to_entries[] |
      select((.key | startswith("//") or startswith("#")) | not) |
      "\(.key)\t\(.value)"
    else empty end
  ' "$_ni_root/package.json" 2>/dev/null)

  if [ -z "$_ni_scripts" ]; then
    _ni_err 'Error: no scripts found in package.json.'
    return 1
  fi

  _ni_selected=$(printf '%s\n' "$_ni_scripts" | column -t -s "$(printf '\t')" | fzf --height=40% --layout=reverse --prompt='script> ')

  _ni_status=$?
  if [ "$_ni_status" -ne 0 ]; then
    return "$_ni_status"
  fi

  _ni_script=$(printf '%s' "$_ni_selected" | awk '{print $1}')

  if [ -z "$_ni_script" ]; then
    _ni_err 'Error: no script selected.'
    return 1
  fi

  _ni_run "$_ni_pm" run "$_ni_script"
}

nup() {
  _ni_pm=$(_ni_require_pm) || return $?
  _ni_parse_args "$@"

  case "$_ni_pm" in
    nub)
      _ni_run nub update -iL "$@"
      ;;
    pnpm)
      _ni_run pnpm update -iL "$@"
      ;;
    bun)
      _ni_run bun update -i "$@"
      ;;
    yarn)
      _ni_yarn_cmd=$(_ni_detect_yarn_cmd)
      case "$_ni_yarn_cmd" in
        'upgrade-interactive') _ni_run yarn upgrade-interactive "$@" ;;
        *) _ni_run yarn up -i "$@" ;;
      esac
      ;;
    npm)
      _ni_run npm upgrade "$@"
      ;;
    *)
      _ni_err "Error: unsupported package manager: $_ni_pm"
      return 1
      ;;
  esac
}

nx() {
  _ni_parse_args "$@"

  if _ni_has_nub; then
    _ni_run nubx "$@"
    return $?
  fi

  _ni_pm=$(_ni_detect_pm)
  case "$_ni_pm" in
    pnpm) _ni_run pnpm dlx "$@" ;;
    bun) _ni_run bunx "$@" ;;
    yarn) _ni_run yarn dlx "$@" ;;
    *) _ni_run npx "$@" ;;
  esac
}
