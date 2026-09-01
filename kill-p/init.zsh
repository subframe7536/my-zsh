#!/usr/bin/env sh

_kill_p_err() {
  printf '%s\n' "$*" >&2
}

_kill_p_require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    _kill_p_err "Error: command not found: $1"
    return 127
  fi
}

_kill_p_setup_env() {
  KILL_P_USER=$(whoami 2>/dev/null)
  [ -n "$KILL_P_USER" ] || KILL_P_USER=${USER-}

  case "$(os)" in
    windows)
      KILL_P_IS_WINDOWS=1
      KILL_P_PS_CMD='ps -W'
      KILL_P_KILL_BIN='/usr/bin/kill'
      KILL_P_KILL_DEFAULT='-f'
      ;;
    *)
      KILL_P_IS_WINDOWS=0
      # This form is used by fzf reload, which runs in a separate shell.
      KILL_P_PS_CMD='ps -f -u "$(whoami 2>/dev/null || printf %s "${USER-}")"'
      KILL_P_KILL_BIN='kill'
      KILL_P_KILL_DEFAULT='-15'
      ;;
  esac
}

_kill_p_list() {
  if [ "$KILL_P_IS_WINDOWS" = '1' ]; then
    ps -W
  else
    ps -f -u "$KILL_P_USER"
  fi
}

# Normalize ps output to: process name, PID, PPID, PGID, Windows PID, command.
# Both supported ps formats expose their field names in the first line.
KILL_P_PROCESS_AWK='
function basename(path,    part_count,parts,name) {
  part_count = split(path, parts, /[\\\\/]/)
  name = parts[part_count]
  sub(/\.[eE][xX][eE]$/, "", name)
  return name
}

function process_name(command,    token,remaining,executable,part_count,parts,part,name) {
  # Windows ps may print an executable path containing spaces without quotes.
  remaining = command
  executable = ""
  while (match(remaining, /[^\\\\/[:space:]"]+\.[eE][xX][eE]/)) {
    executable = substr(remaining, RSTART, RLENGTH)
    remaining = substr(remaining, RSTART + RLENGTH)
  }
  if (executable != "") return basename(executable)

  token = command
  sub(/[[:space:]].*$/, "", token)
  name = basename(token)
  if (name != "" && name !~ /^[0-9]+$/) return name

  part_count = split(command, parts, /[[:space:]]+/)
  for (part = 1; part <= part_count; part++) {
    name = basename(parts[part])
    if (name != "" && name !~ /^[0-9]+$/) return name
  }
  return "?"
}

NR == 1 {
  for (column = 1; column <= NF; column++) {
    field = toupper($column)
    if (field == "PID" && pid_column == 0) pid_column = column
    else if (field == "PPID" && ppid_column == 0) ppid_column = column
    else if (field == "PGID" && pgid_column == 0) pgid_column = column
    else if ((field == "WINPID" || field == "WPID") && wpid_column == 0) wpid_column = column
    else if ((field == "CMD" || field == "COMMAND" || field == "COMM") && command_column == 0) command_column = column
  }
  if (pid_column == 0) pid_column = 1
  if (command_column == 0) command_column = NF
  print "PROCESS\tPID\tPPID\tPGID\tWPID\tCOMMAND"
  next
}

{
  pid = (pid_column <= NF ? $pid_column : "")
  if (pid == "") next

  command = (command_column <= NF ? $command_column : "")
  for (column = command_column + 1; column <= NF; column++) {
    command = command " " $column
  }

  ppid = (ppid_column > 0 && ppid_column <= NF ? $ppid_column : "")
  pgid = (pgid_column > 0 && pgid_column <= NF ? $pgid_column : "")
  wpid = (wpid_column > 0 && wpid_column <= NF ? $wpid_column : "")
  print process_name(command) "\t" pid "\t" ppid "\t" pgid "\t" wpid "\t" command
}
'

KILL_P_TABLE_AWK='
BEGIN { FS = "\t" }

NR == 1 {
  if (is_windows) {
    printf "%-24s %-8s %-8s %-8s %-8s\tPID\tCOMMAND\n", "Process", "WPID", "PID", "PPID", "PGID"
  } else {
    printf "%-24s %-8s %-8s %-8s\tPID\tCOMMAND\n", "Process", "PID", "PPID", "PGID"
  }
  next
}

{
  if (is_windows) {
    display = sprintf("%-24s %-8s %-8s %-8s %-8s", $1, $5, $2, $3, $4)
  } else {
    display = sprintf("%-24s %-8s %-8s %-8s", $1, $2, $3, $4)
  }
  print display "\t" $2 "\t" $6
}
'

_kill_p_processes() {
  _kill_p_list | awk -v is_windows="$KILL_P_IS_WINDOWS" "$KILL_P_PROCESS_AWK"
}

_kill_p_table() {
  _kill_p_processes | awk -v is_windows="$KILL_P_IS_WINDOWS" "$KILL_P_TABLE_AWK"
}

_kill_p_build_table_cmd() {
  _kill_p_process_awk=$(printf '%s' "$KILL_P_PROCESS_AWK" | tr '\n' ' ')
  _kill_p_table_awk=$(printf '%s' "$KILL_P_TABLE_AWK" | tr '\n' ' ')

  printf "%s | awk -v is_windows=%s '%s' | awk -v is_windows=%s '%s'\n" \
    "$KILL_P_PS_CMD" "$KILL_P_IS_WINDOWS" "$_kill_p_process_awk" \
    "$KILL_P_IS_WINDOWS" "$_kill_p_table_awk"
}

_kill_p_direct() {
  _kill_p_query=$1
  _kill_p_pids=$(
    _kill_p_processes | awk -F '\t' -v query="$_kill_p_query" '
      BEGIN {
        normalized_query = query
        sub(/\.[eE][xX][eE]$/, "", normalized_query)
        normalized_query = tolower(normalized_query)
      }
      NR > 1 && ($2 == query || tolower($1) == normalized_query) {
        print $2
      }
    '
  )

  if [ -z "$_kill_p_pids" ]; then
    _kill_p_err "No exact-match process found: '$_kill_p_query'"
    return 1
  fi

  _kill_p_count=$(printf '%s\n' "$_kill_p_pids" | awk 'END { print NR }')
  printf 'Killing %s process(es): %s\n' \
    "$_kill_p_count" "$(printf '%s\n' "$_kill_p_pids" | tr '\n' ' ')"

  _kill_p_failed=0
  while IFS= read -r _kill_p_pid; do
    [ -n "$_kill_p_pid" ] || continue
    "$KILL_P_KILL_BIN" "$KILL_P_KILL_DEFAULT" "$_kill_p_pid" || _kill_p_failed=1
  done <<EOF
$_kill_p_pids
EOF

  return "$_kill_p_failed"
}

_kill_p_interactive() {
  _kill_p_require_cmd fzf || return $?

  _kill_p_table_cmd=$(_kill_p_build_table_cmd)
  _kill_p_enter_cmd="awk -F '\t' 'NF { print \$2 }' {+f} | while IFS= read -r pid; do $KILL_P_KILL_BIN $KILL_P_KILL_DEFAULT \"\$pid\"; done"
  _kill_p_force_cmd="awk -F '\t' 'NF { print \$2 }' {+f} | while IFS= read -r pid; do $KILL_P_KILL_BIN -9 \"\$pid\"; done"

  if [ "$KILL_P_IS_WINDOWS" = '1' ]; then
    _kill_p_header='[Enter] Force Kill | [Tab] Select | [Ctrl-R] Reload'
  else
    _kill_p_header='[Enter] Kill | [Ctrl-X] Force | [Tab] Select | [Ctrl-R] Reload'
  fi

  set -- \
    --header-lines=1 \
    --layout=reverse \
    --info=inline \
    --height=80% \
    --multi \
    --delimiter="$(printf '\t')" \
    --with-nth=1 \
    --prompt='Kill Process > ' \
    --header="$_kill_p_header" \
    --preview='printf "%s\\n" {} | cut -f3-' \
    --preview-window=down:4:wrap \
    --bind "ctrl-r:reload($_kill_p_table_cmd)" \
    --bind "enter:execute-silent($_kill_p_enter_cmd)+reload($_kill_p_table_cmd)+clear-selection"

  if [ "$KILL_P_IS_WINDOWS" != '1' ]; then
    set -- "$@" --bind "ctrl-x:execute-silent($_kill_p_force_cmd)+reload($_kill_p_table_cmd)+clear-selection"
  fi

  _kill_p_table | fzf "$@"
}

kill-p() {
  _kill_p_query=$*

  _kill_p_setup_env
  _kill_p_require_cmd awk || return $?
  _kill_p_require_cmd ps || return $?

  if [ "$KILL_P_IS_WINDOWS" = '1' ]; then
    if [ ! -x "$KILL_P_KILL_BIN" ]; then
      _kill_p_err "Error: command not found: $KILL_P_KILL_BIN"
      return 127
    fi
  else
    _kill_p_require_cmd "$KILL_P_KILL_BIN" || return $?
  fi

  if [ -n "$_kill_p_query" ]; then
    _kill_p_direct "$_kill_p_query"
  else
    _kill_p_interactive
  fi
}
