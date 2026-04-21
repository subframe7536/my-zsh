#!/usr/bin/env zsh

ghdns() {
  local REMOTE_URL="https://github.133909.best/github.com/ineo6/hosts/raw/refs/heads/master/hosts"
  local MARKER_START="# GitHub Host Start"
  local MARKER_END="# GitHub Host End"
  local HOSTS_FILE=""
  local DRY_RUN=false
  local PLATFORM=""

  # --- Parse Arguments ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run|-n) DRY_RUN=true; shift ;;
      -h|--help)
        cat <<EOF
Usage: ghdns [--dry-run]

Update GitHub DNS from $REMOTE_URL

Options:
  -n, --dry-run   Preview changes without modifying
  -h, --help      Show this help message

Note: sudo privileges required for actual update.
EOF
        return 0
        ;;
      *) echo "❌ Unknown option: $1" >&2; return 1 ;;
    esac
  done

  # --- Platform Detection ---
  _detect_platform() {
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] || \
       [[ -n "$GIT_BASH_VERSION" ]] || [[ "$(uname -s)" =~ ^MINGW ]]; then
      echo "windows"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      echo "macos"
    elif [[ "$OSTYPE" == "linux"* ]]; then
      echo "linux"
    else
      echo "unknown"
    fi
  }

  PLATFORM=$(_detect_platform)
  case "$PLATFORM" in
    windows) HOSTS_FILE="/c/Windows/System32/drivers/etc/hosts" ;;
    macos|linux) HOSTS_FILE="/etc/hosts" ;;
    *) echo "× Unsupported platform: $OSTYPE" >&2; return 1 ;;
  esac

  _error() { echo "× ERROR: $*" >&2 ; }

  _require_sudo() {
    [[ $EUID -eq 0 ]] && return 0
    if [[ "$DRY_RUN" == true ]]; then
      echo "[DRY-RUN] Would require sudo for $HOSTS_FILE"
      return 0
    fi
    if ! sudo -v 2>/dev/null; then
      _error "sudo required"
      return 1
    fi
  }

  _check_prerequisites() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v sed >/dev/null 2>&1 || missing+=("sed")
    [[ ${#missing[@]} -gt 0 ]] && { _error "Missing: ${missing[*]}"; return 1; }
    [[ ! -f "$HOSTS_FILE" ]] && { _error "Not found: $HOSTS_FILE"; return 1; }
    return 0
  }

  _update_hosts() {
    echo "Fetching latest hosts from: $REMOTE_URL"

    # 1. Fetch new content (no sudo needed)
    local new_content
    new_content=$(curl -sSL --connect-timeout 10 "$REMOTE_URL") || {
      _error "Failed to fetch remote hosts"
      return 1
    }

    if [[ -z "$new_content" ]] || ! echo "$new_content" | grep -q "$MARKER_START"; then
      _error "Invalid/empty content downloaded"
      return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
      echo "[DRY-RUN] These records will add\n\n$new_content\n"
      return 0
    fi

    # 2. Build final content:
    #    - Read current hosts
    #    - Remove old GitHub520 block
    #    - Append new content
    #    All in ONE subshell, then pipe to sudo tee
    local final_content
    final_content=$(
      # Filter out old entries
      sed "/${MARKER_START}/,/${MARKER_END}/d" "$HOSTS_FILE"

      # 2. extract new content
      awk "/${MARKER_START}/,/${MARKER_END}/" <<< "$new_content"
    ) || {
      _error "Failed to build final hosts content"
      return 1
    }

    # 3. Write with `sudo tee` (atomic write)
    if ! printf '%s\n' "$final_content" | sudo tee "$HOSTS_FILE" >/dev/null; then
      _error "Failed to write hosts file"
      return 1
    fi

    echo "✓ Hosts updated successfully"
    return 0
  }

  _flush_dns() {
    [[ "$DRY_RUN" == true ]] && { echo "[DRY-RUN] Would flush DNS"; return 0; }

    case "$PLATFORM" in
      windows)
        MSYS_NO_PATHCONV=1 cmd.exe /c "ipconfig /flushdns" >/dev/null 2>&1 && \
          echo "✓ DNS flushed" || echo "⚠️  DNS flush skipped"
        ;;
      macos)
        sudo killall -HUP mDNSResponder 2>/dev/null && echo "✓ DNS flushed" || true
        ;;
      linux)
        sudo systemd-resolve --flush-caches 2>/dev/null && echo "✓ DNS flushed" || \
        sudo nscd restart 2>/dev/null && echo "✓ DNS flushed" || echo "⚠️  Manual flush may be needed"
        ;;
    esac
  }

  # --- Main ---
  echo "GitHub Host Updater [Platform: $PLATFORM]"
  _require_sudo || return 1
  _check_prerequisites || return 1

  _update_hosts || return 1

  if [[ "$DRY_RUN" != true ]]; then
    _flush_dns
    echo "✓ Update complete! Verify: ping github.com"
  else
    echo "✓ Dry-run done. No changes made."
  fi
  return 0
}
