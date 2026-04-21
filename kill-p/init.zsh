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
  if [ -z "$KILL_P_USER" ]; then
    KILL_P_USER=${USER-}
  fi

  case "${OSTYPE-}" in
    msys*|cygwin*)
      KILL_P_IS_WINDOWS=1
      KILL_P_PS_CMD='ps -W'
      KILL_P_KILL_BIN='/usr/bin/kill'
      KILL_P_KILL_DEFAULT='-f'
      ;;
    *)
      KILL_P_IS_WINDOWS=0
      KILL_P_PS_CMD="ps -f -u $KILL_P_USER"
      KILL_P_KILL_BIN='kill'
      KILL_P_KILL_DEFAULT='-15'
      ;;
  esac
}

_kill_p_list() {
  eval "$KILL_P_PS_CMD"
}

_kill_p_build_table_cmd() {
  _kill_p_table_awk='function proc_name_from_cmd(cmd,    token,n,path_parts,name,tmp,exe,seg,m,p){token=cmd;sub(/[[:space:]].*$/,"",token);n=split(token,path_parts,/[\\\/]/);name=path_parts[n];sub(/\.[eE][xX][eE]$/,"",name);if(name!=""&&name!~/^[0-9]+$/)return name;tmp=cmd;exe="";while(match(tmp,/[^\\\/[:space:]"]+\.[eE][xX][eE]/)){exe=substr(tmp,RSTART,RLENGTH);tmp=substr(tmp,RSTART+RLENGTH)}if(exe!=""){sub(/\.[eE][xX][eE]$/,"",exe);if(exe!="")return exe}m=split(cmd,seg,/[[:space:]]+/);for(p=1;p<=m;p++){if(seg[p]==""||seg[p]~/^[0-9]+$/)continue;n=split(seg[p],path_parts,/[\\\/]/);name=path_parts[n];sub(/\.[eE][xX][eE]$/,"",name);if(name!="")return name}return "?"}NR==1{for(i=1;i<=NF;i++){h=toupper($i);if(h=="PID"&&pid_col==0)pid_col=i;else if(h=="PPID"&&ppid_col==0)ppid_col=i;else if(h=="PGID"&&pgid_col==0)pgid_col=i;else if((h=="WINPID"||h=="WPID")&&wpid_col==0)wpid_col=i;else if((h=="CMD"||h=="COMMAND"||h=="COMM")&&cmd_col==0)cmd_col=i}if(pid_col==0)pid_col=1;if(cmd_col==0)cmd_col=NF;if(is_windows){header=sprintf("%-24s %-8s %-8s %-8s %-8s","Process","WPID","PID","PPID","PGID")}else{header=sprintf("%-24s %-8s %-8s %-8s","Process","PID","PPID","PGID")}print header "\tPID\tCOMMAND";next}{pid=(pid_col<=NF?$pid_col:"");if(pid=="")next;ppid=(ppid_col>0&&ppid_col<=NF?$ppid_col:"");pgid=(pgid_col>0&&pgid_col<=NF?$pgid_col:"");wpid=(wpid_col>0&&wpid_col<=NF?$wpid_col:"");cmd=(cmd_col<=NF?$cmd_col:"");for(i=cmd_col+1;i<=NF;i++)cmd=cmd" "$i;name=proc_name_from_cmd(cmd);if(is_windows){display=sprintf("%-24s %-8s %-8s %-8s %-8s",name,wpid,pid,ppid,pgid)}else{display=sprintf("%-24s %-8s %-8s %-8s",name,pid,ppid,pgid)}print display "\t" pid "\t" cmd}'

  printf '%s\n' "$KILL_P_PS_CMD | awk -v is_windows=$KILL_P_IS_WINDOWS '$_kill_p_table_awk'"
}

_kill_p_direct() {
  _kill_p_query=$1
  _kill_p_pids=$(
    _kill_p_list | awk -v q="$_kill_p_query" '
      BEGIN {
        q_norm = q
        sub(/\.[eE][xX][eE]$/, "", q_norm)
        q_lower = tolower(q_norm)
      }
      function proc_name_from_cmd(cmd,    token,n,path_parts,name,tmp,exe,seg,m,p) {
        token = cmd
        sub(/[[:space:]].*$/, "", token)
        n = split(token, path_parts, /[\\\/]/)
        name = path_parts[n]
        sub(/\.[eE][xX][eE]$/, "", name)
        if (name != "" && name !~ /^[0-9]+$/) return name

        tmp = cmd
        exe = ""
        while (match(tmp, /[^\\\/[:space:]"]+\.[eE][xX][eE]/)) {
          exe = substr(tmp, RSTART, RLENGTH)
          tmp = substr(tmp, RSTART + RLENGTH)
        }
        if (exe != "") {
          sub(/\.[eE][xX][eE]$/, "", exe)
          if (exe != "") return exe
        }

        m = split(cmd, seg, /[[:space:]]+/)
        for (p = 1; p <= m; p++) {
          if (seg[p] == "" || seg[p] ~ /^[0-9]+$/) continue
          n = split(seg[p], path_parts, /[\\\/]/)
          name = path_parts[n]
          sub(/\.[eE][xX][eE]$/, "", name)
          if (name != "") return name
        }
        return "?"
      }
      NR == 1 {
        for (i = 1; i <= NF; i++) {
          h = toupper($i)
          if (h == "PID" && pid_col == 0) pid_col = i
          else if ((h == "CMD" || h == "COMMAND" || h == "COMM") && cmd_col == 0) cmd_col = i
        }
        if (pid_col == 0) pid_col = 1
        if (cmd_col == 0) cmd_col = NF
        next
      }
      {
        pid = (pid_col <= NF ? $pid_col : "")
        if (pid == "") next
        cmd = (cmd_col <= NF ? $cmd_col : "")
        for (i = cmd_col + 1; i <= NF; i++) {
          cmd = cmd " " $i
        }
        base_name = proc_name_from_cmd(cmd)

        if (pid == q_norm || tolower(base_name) == q_lower) {
          print pid
        }
      }
    '
  )

  if [ -z "$_kill_p_pids" ]; then
    _kill_p_err "No exact-match process found: '$_kill_p_query'"
    return 1
  fi

  _kill_p_count=$(printf '%s\n' "$_kill_p_pids" | awk 'NF { c += 1 } END { print c + 0 }')
  printf 'Killing %s process(es): %s\n' "$_kill_p_count" "$(printf '%s\n' "$_kill_p_pids" | tr '\n' ' ')"

  _kill_p_failed=0
  while IFS= read -r _kill_p_pid; do
    [ -n "$_kill_p_pid" ] || continue
    "$KILL_P_KILL_BIN" "$KILL_P_KILL_DEFAULT" "$_kill_p_pid" || _kill_p_failed=1
  done <<EOF
$_kill_p_pids
EOF

  if [ "$_kill_p_failed" -ne 0 ]; then
    return 1
  fi
  return 0
}

_kill_p_interactive() {
  _kill_p_require_cmd fzf || return $?

  _kill_p_header='[Enter] Kill | [Ctrl-X] Force | [Tab] Select | [Ctrl-R] Reload'
  if [ "$KILL_P_IS_WINDOWS" = '1' ]; then
    _kill_p_header='[Enter] Force Kill | [Tab] Select | [Ctrl-R] Reload'
  fi

  _kill_p_table_cmd=$(_kill_p_build_table_cmd)

  _kill_p_enter_cmd="awk -F '\t' '{print \$2}' {+f} | awk 'NF { print }' | while read -r pid; do $KILL_P_KILL_BIN $KILL_P_KILL_DEFAULT \"\$pid\"; done"
  _kill_p_force_cmd="awk -F '\t' '{print \$2}' {+f} | awk 'NF { print }' | while read -r pid; do $KILL_P_KILL_BIN -9 \"\$pid\"; done"

  if [ "$KILL_P_IS_WINDOWS" = '1' ]; then
    eval "$_kill_p_table_cmd" | fzf \
      --header-lines=1 \
      --layout=reverse \
      --info=inline \
      --height=80% \
      --multi \
      --delimiter="$(printf '\t')" \
      --with-nth='1' \
      --prompt='Kill Process > ' \
      --header="$_kill_p_header" \
      --preview 'printf "%s\n" {} | cut -f3-' \
      --preview-window=down:4:wrap \
      --bind "ctrl-r:reload($_kill_p_table_cmd)" \
      --bind "enter:execute-silent($_kill_p_enter_cmd)+reload($_kill_p_table_cmd)+clear-selection"
  else
    eval "$_kill_p_table_cmd" | fzf \
      --header-lines=1 \
      --layout=reverse \
      --info=inline \
      --height=80% \
      --multi \
      --delimiter="$(printf '\t')" \
      --with-nth='1' \
      --prompt='Kill Process > ' \
      --header="$_kill_p_header" \
      --preview 'printf "%s\n" {} | cut -f3-' \
      --preview-window=down:4:wrap \
      --bind "ctrl-r:reload($_kill_p_table_cmd)" \
      --bind "enter:execute-silent($_kill_p_enter_cmd)+reload($_kill_p_table_cmd)+clear-selection" \
      --bind "ctrl-x:execute-silent($_kill_p_force_cmd)+reload($_kill_p_table_cmd)+clear-selection"
  fi
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
    return $?
  fi

  _kill_p_interactive
}
