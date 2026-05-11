# ~/.local/share/bash-completion/completions/tms
# or /usr/local/share/bash-completion/completions/tms

_tms_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"

  local active
  active=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -vE '^.*-[0-9]+$' || true)

  if [[ -z "${active}" ]]; then
    COMPREPLY=($(compgen -W "init" -- "${cur}"))
    return 0
  fi

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "init ${active}" -- "${cur}"))
  elif [[ ${COMP_CWORD} -eq 2 ]]; then
    if [[ "${prev}" == "init" ]]; then
      COMPREPLY=($(compgen -W "--reset --dry-run" -- "${cur}"))
      return 0
    fi
    local windows
    windows=$(tmux list-windows -t "${prev}" -F "#{window_name}" 2>/dev/null || true)
    COMPREPLY=($(compgen -W "${windows}" -- "${cur}"))
  fi
}

complete -F _tms_complete tms
