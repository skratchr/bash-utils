#!/bin/bash
#
# Library that provides conversion functions.
#
# requires:
#  bash, sed, awk, tr
#

convert::to_snake_case() {
  echo "$1" |
    sed -E 's/([A-Z]+)([A-Z][a-z])/\1_\2/g' |
    sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' |
    sed 's/-/_/g' |
    awk '{ print tolower($0) }'
}

convert::to_dash_case() {
  echo "$1" |
    sed -E 's/([A-Z]+)([A-Z][a-z])/\1_\2/g' |
    sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' |
    sed 's/_/-/g' |
    awk '{ print tolower($0) }'
}

convert::to_camel_case() {
  local str="${1}"
  local camelized="" char=""
  local last_found=0
  # Manually loop through characters. This conversion has enough edge-cases that
  # other solutions like awk requires logic as well, at which point it becomes
  # both more complex and less maintainable.
  for ((i = 0; i < ${#str}; i++)); do
    [[ "${str:$i:1}" == "-" || ("${str:$i:1}" == "_" && $i -gt 0) ]] && {
      char="$(echo "${str:$((i + 1)):1}" | tr '[:lower:]' '[:upper:]')"
      camelized="${camelized}${str:$last_found:$((i - last_found))}${char}"
      last_found=$((i + 2))
    }
  done

  local len="${#str}"
  camelized="${camelized}${str:$last_found:$((len - last_found))}"
  # note: tolower on the first char is safe even when the string starts with "_"
  # since tolower("_") == "_
  echo "${camelized}" |
    awk '{ print tolower(substr($0,1,1))substr($0,2) }'
}

convert::to_pascal_case() {
  convert::to_camel_case "${1}" |
    awk '{ print toupper(substr($0,1,1))substr($0,2) }'
}

convert::ipv4_to_int() {
  echo "$1" |
    awk '{
      num = (($1*2^24) + ($2*2^16) + ($3*2^8) + $4)
    } END { print num }' FS=.
}

convert::int_to_ipv4() {
  # no bitwise and exists, mod operator used instead.
  echo "$1" |
    awk '{
      octet1 = (($1/2^24) % 256)
      octet2 = (($1/2^16) % 256)
      octet3 = (($1/2^8) % 256)
      octet4 = ($1 %256)
    } END { printf("%d.%d.%d.%d\n",octet1,octet2,octet3,octet4) }'
}
