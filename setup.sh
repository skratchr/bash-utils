#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly project_root
# binary-like scripts follow the convention ./name/name, for binaries that
# provides bash-completions the convention is to allow a --completion cli argument
# which outputs the absolute path of the script
declare -a bins=("tms" "bt")
readonly bins

# library-like files that provide functions to the shell follows the convention
# key = lib-name, value = list of files to source separated by whitespace
declare -A libs=(
  ["conv"]="convert.sh"
  # ["netw"]="config.sh fw.sh"
)
readonly libs

#
# install binaries
#
for t in "${bins[@]}"; do
  sudo rm -f "/usr/local/bin/${t}"
  chmod +x "${project_root}/${t}/${t}"
  sudo ln -s "${project_root}/${t}/${t}" "/usr/local/bin/${t}"

  if [[ ! -f "${HOME}/.bash_profile" ]]; then
    echo "${HOME}/.bash_profile not found, skip bash-completions for ${t}" >&2
    continue
  fi

  marker="# ${t} bash completions added by bash-utils"
  comp_path=""
  read -r comp_path < <("${project_root}/${t}/${t}" --completion)

  if [[ -n "${comp_path}" ]]; then
    if grep -q "${marker}" "${HOME}/.bash_profile"; then
      continue
    fi
    cat >>"${HOME}/.bash_profile" <<EOF

${marker}
if which ${t} > /dev/null; then
    source "\$(${t} --completion)"
fi
EOF
  fi
done

#
# add libraries to be sourced on the next new shell
#
if [[ ! -f "${HOME}/.bash_profile" ]]; then
  echo "${HOME}/.bash_profile not found, skip sourcing utility functions" >&2
  exit 0
fi
for k in "${!libs[@]}"; do
  read -r -a files <<<"${libs[${k}]}"
  for f in "${files[@]}"; do
    if ! grep -q "# ${k}/${f} library added by bash-utils" "${HOME}/.bash_profile"; then
      cat >>"${HOME}/.bash_profile" <<EOF
source "${project_root}/${k}/${f}" # ${k}/${f} library added by bash-utils
EOF
    fi
  done
done
