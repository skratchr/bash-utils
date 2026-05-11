#!/usr/bin/env bash
#
# bt-completion.bash — bash completion for bt (bash test runner)
#
# Installation:
#   System-wide:  cp bt-completion.bash /etc/bash_completion.d/bt
#   Per-user:     source bt-completion.bash  (add to ~/.bashrc for persistence)

_bt() {
  local cur prev words
  _init_completion || return

  local flags="--help --debug"

  case "${prev}" in
  --help)
    # nothing follows --help
    return
    ;;
  esac

  case "${cur}" in
  -*)
    # complete flags
    COMPREPLY=($(compgen -W "${flags}" -- "${cur}"))
    ;;
  *)
    # complete directories only
    COMPREPLY=($(compgen -d -- "${cur}"))
    # append a trailing slash so the user can keep tabbing into subdirs
    [[ "${#COMPREPLY[@]}" -eq 1 ]] && COMPREPLY[0]+="/"
    compopt -o nospace
    ;;
  esac
}

complete -F _bt bt
