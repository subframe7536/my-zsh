#!/usr/bin/env sh

# Print a normalized operating system name for use by plugin modules.
_os_detect() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) printf '%s\n' 'windows' ;;
    Darwin*) printf '%s\n' 'macos' ;;
    Linux*) printf '%s\n' 'linux' ;;
    *)
      case "${OSTYPE-}" in
        msys*|cygwin*|mingw*) printf '%s\n' 'windows' ;;
        darwin*) printf '%s\n' 'macos' ;;
        linux*) printf '%s\n' 'linux' ;;
        *) printf '%s\n' 'unknown' ;;
      esac
      ;;
  esac
}

os() {
  if [ "$#" -ne 0 ]; then
    printf 'usage: os\n' >&2
    return 2
  fi

  _os_detect
}
