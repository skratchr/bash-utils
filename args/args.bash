#!/bin/bash
# Portable library for extracting and converting arguments passedo
# through the cli into usable variables. Allowed arguments are
# defined by the caller script and passed on along as input.
#
# requires:
#  bash >= 2.05b
#
# Deliberately avoided so the floor stays low and the library runs
# wherever bash does:
#   [[ =~ ]]            bash 3.0  — `case` globs used instead
#   printf -v           bash 3.1  — validated-name `eval` used instead
#   arr+=( x )          bash 3.1  — arr[${#arr[@]}]=x used instead
#   associative arrays  bash 4.0
#   < <( ... )          needs /dev/fd; absent in some chroots and jails
#   <<< herestring      writes a temp file; fails on a read-only TMPDIR
#

declare -a REQUIRED_ARGS
declare -a EXTRACTABLE_ARGS
REQUIRED_ARGS=()
EXTRACTABLE_ARGS=()

declare -a _EA_REFS
_EA_REFS=()
_EA_VARNAME=""

_ea_die() {
  local msg="$*"
  printf "%s\n" "[ERROR] ${msg}." 1>&2
  printf "%s\n" "Aborting script..." 1>&2
  exit 253
}

# A name reaches `eval` on the next line, so this is load-bearing, not
# hygiene: without it `--PATH /tmp` overwrites PATH, and a name holding
# a metacharacter would execute.
_ea_is_identifier() {
  case "${1}" in
  '' | [!a-zA-Z_]* | *[!a-zA-Z0-9_]*)
    return 1
    ;;
  PATH | IFS | HOME | PWD | OLDPWD | SHELL | UID | EUID | PPID | RANDOM | SECONDS | LINENO | FUNCNAME | BASH*)
    return 1
    ;;
  esac
  return 0
}

_ea_is_number() {
  case "${1}" in
  '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

_ea_assign() {
  local __ea_name="${1}"
  local __ea_val="${2}"

  case "${__ea_name}" in
  *'['*']')
    _ea_is_identifier "${__ea_name%%[*}" ||
      _ea_die "Invalid variable name: ${__ea_name}"
    ;;
  *)
    _ea_is_identifier "${__ea_name}" ||
      _ea_die "Invalid or reserved variable name: ${__ea_name}"
    ;;
  esac

  eval "${__ea_name}=\${__ea_val}"
}

_ea_define_arg_value() {
  local __arg="ref_${1}"
  local __arg_idx __arg_base __i __l __n __ref_val

  _EA_VARNAME=""
  # Indirect expansion with a default, so an undeclared argument is an
  # empty string here rather than a crash in a caller running set -u.
  __ref_val="${!__arg-}"

  if [[ "${__ref_val}" == "flaggable" ]]; then
    _EA_VARNAME="flaggable"
  elif [[ "${__ref_val}" == "0" ]]; then
    _EA_VARNAME="${__arg#*ref_}"
  elif [[ -z "${__ref_val}" ]]; then
    __arg="${__arg#ref_}"

    # A list arg keeps its own name and takes the next free slot, so it is
    # resolved before the index path strips trailing digits — otherwise
    # --tag2 on a list would be read as index 2 of a list called "tag".
    __l="l_${__arg}"
    if [[ "${!__l-}" == "list" ]]; then
      __n="n_${__arg}"
      _EA_VARNAME="${__arg}[${!__n}]"
      eval "${__n}=\$(( \${${__n}} + 1 ))"
      return 0
    fi

    # indexed args do not use the standard pattern, they mimic a collection
    __arg_idx="${__arg##*[!0-9]}"
    _ea_is_number "${__arg_idx}" ||
      _ea_die "Unknown argument: --${1}"
    __arg_base="${__arg:0:$((${#__arg} - ${#__arg_idx}))}"

    __i="i_${__arg_base}"
    [[ "${!__i-}" == "index" ]] ||
      _ea_die "Type mismatch: ${__arg_base} needs to be index"

    _EA_VARNAME="${__arg_base}[${__arg_idx}]"
  fi
}

_ea_declared() {
  local __n="${1}"
  local __r="ref_${__n}" __i="i_${__n}" __l="l_${__n}"
  [[ -n "${!__r-}" || -n "${!__i-}" || -n "${!__l-}" ]]
}

_ea_create_reference_variable() {
  local __val="${1%%;*}"
  local __name="${__val//-/_}"
  local __ref_val=0
  local __ref_key="ref_${__name}"
  local __type=""
  local __tags __t __old_ifs

  _ea_declared "${__name}" &&
    _ea_die "Duplicate declaration of ${__val} in EXTRACTABLE_ARGS"

  case "${1}" in
  *';'*)
    __tags="${1#*;}"
    __old_ifs="${IFS}"
    IFS=';'
    set -f
    # Intentional split on IFS with globbing disabled — the herestring
    # form needs a writable TMPDIR, and mapfile is bash 4.
    # shellcheck disable=SC2206
    __tags=(${__tags})
    set +f
    IFS="${__old_ifs}"
    for __t in "${__tags[@]}"; do
      case "${__t}" in
      flag)
        [[ -z "${__type}" ]] || _ea_die "Conflicting tags on ${__val}: ${__type} and flag"
        __type="flag"
        __ref_val="flaggable"
        ;;
      index)
        [[ -z "${__type}" ]] || _ea_die "Conflicting tags on ${__val}: ${__type} and index"
        __type="index"
        __ref_val="index"
        __ref_key="i_${__name}"
        ;;
      list)
        [[ -z "${__type}" ]] || _ea_die "Conflicting tags on ${__val}: ${__type} and list"
        __type="list"
        __ref_val="list"
        __ref_key="l_${__name}"
        ;;
      required)
        REQUIRED_ARGS[${#REQUIRED_ARGS[@]}]="${__val}"
        ;;
      *)
        _ea_die "Invalid tag: ${__t}"
        ;;
      esac
    done
    ;;
  esac

  _ea_assign "${__ref_key}" "${__ref_val}"
  _EA_REFS[${#_EA_REFS[@]}]="${__ref_key}"

  if [[ "${__type}" == "list" ]]; then
    _ea_is_identifier "${__name}" ||
      _ea_die "Invalid or reserved variable name: ${__name}"
    eval "${__name}=()"
    _ea_assign "n_${__name}" 0
    _EA_REFS[${#_EA_REFS[@]}]="n_${__name}"
  fi
}

_ea_define_reference_variables() {
  local __value __name __idx __base __i

  REQUIRED_ARGS=()
  for __value in "${EXTRACTABLE_ARGS[@]}"; do
    _ea_create_reference_variable "${__value}"
  done

  # Second pass, because an index declaration may come after the name it
  # shadows: --tag1 can only ever reach one of `tag;index` and `tag1`,
  # and which one depends on declaration order rather than on intent.
  for __value in "${EXTRACTABLE_ARGS[@]}"; do
    __name="${__value%%;*}"
    __name="${__name//-/_}"
    __idx="${__name##*[!0-9]}"
    _ea_is_number "${__idx}" || continue
    __base="${__name:0:$((${#__name} - ${#__idx}))}"
    [[ -n "${__base}" ]] || continue
    __i="i_${__base}"
    [[ "${!__i-}" == "index" ]] &&
      _ea_die "${__name} is unreachable: ${__base};index already claims --${__base} plus a number"
  done
  return 0
}

_ea_contains() {
  local __needle="${1}"
  shift
  local __item
  for __item in "$@"; do
    [[ "${__item}" == "${__needle}" ]] && return 0
  done
  return 1
}

_ea_check_required_args() {
  local __req_arg
  for __req_arg in "${REQUIRED_ARGS[@]}"; do
    _ea_contains "${__req_arg}" "$@" ||
      _ea_die "Missing argument --${__req_arg}"
  done
}

_ea_create_var() {
  local __arg="${1}"
  local __val="${2}"
  local __var

  _ea_define_arg_value "${__arg//-/_}"
  __var="${_EA_VARNAME}"

  [[ -n "${__var}" ]] || _ea_die "Invalid argument: --${__arg}"

  if [[ "${__var}" == "flaggable" ]]; then
    case "${__val}" in
    true | false)
      __var="${__arg//-/_}"
      ;;
    *)
      _ea_die "Invalid value: ${__val}, --${__arg} is a flag and takes none"
      ;;
    esac
  fi

  _ea_assign "${__var}" "${__val}"
}

######################################
# Converts arguments passed on the command line into variables
# according to a list passed in when calling.
# Optionally allowed arguments can be suffixed to mark that the
# argument specification/generated variable should represent a
# different type.
#
# defined in list:   generated output:    cli:
#  arg;flag          true/false value     --arg
#  arg;index         array, caller-numbered  --arg<n> value
#  arg;list          array, encounter order  --arg value --arg value
#
# adding the required flag makes the argument required
#  sample: arg;required
#
# Everything after a bare -- is positional, whatever it looks like.
#
# Globals:
#   EXTRACTABLE_ARGS
#   REQUIRED_ARGS
#   args
# Arguments:
#   $@ array of arguments
# Returns:
#   None
#######################################
args::extract() {
  [[ "${#EXTRACTABLE_ARGS[@]}" -eq 0 ]] && return 0

  local __arg __value __next __ref __rest
  local __end_of_opts=false
  declare -a __cmd_args
  declare -a __parsed_args
  __cmd_args=()
  __parsed_args=()

  _ea_define_reference_variables

  while [[ "${#}" -gt 0 ]]; do
    __value="${1}"
    shift
    __next="${1-}"

    if [[ "${__end_of_opts}" == "true" ]]; then
      __cmd_args[${#__cmd_args[@]}]="${__value}"
      continue
    fi

    case "${__value}" in
    --)
      __end_of_opts=true
      ;;
    --*)
      __arg="${__value#--}"
      case "${__arg}" in
      *'='*)
        __value="${__arg#*=}"
        __arg="${__arg%%=*}"
        ;;
      *)
        # A leading -- and nothing else marks the next option; a
        # single leading dash does not, so negative values survive.
        case "${__next}" in
        --*)
          __value=true
          ;;
        '')
          if [[ "${#}" -eq 0 ]]; then
            __value=true
          else
            __value="${1}"
            shift
          fi
          ;;
        *)
          __value="${1}"
          shift
          ;;
        esac
        ;;
      esac
      _ea_create_var "${__arg}" "${__value}"
      __parsed_args[${#__parsed_args[@]}]="${__arg}"
      ;;
    -?*)
      _ea_die "Short options are not supported: ${__value}"
      ;;
    *)
      __cmd_args[${#__cmd_args[@]}]="${__value}"
      ;;
    esac
  done

  if [[ "${#REQUIRED_ARGS[@]}" -gt 0 ]]; then
    if [[ "${#__parsed_args[@]}" -gt 0 ]]; then
      _ea_check_required_args "${__parsed_args[@]}"
    else
      _ea_check_required_args ""
    fi
  fi

  # Assigned element by element rather than through `read -ra`, which
  # would re-split values on IFS and lose any that contain spaces.
  args=()
  if [[ "${#__cmd_args[@]}" -gt 0 ]]; then
    for __rest in "${__cmd_args[@]}"; do
      args[${#args[@]}]="${__rest}"
    done
  fi

  for __ref in "${_EA_REFS[@]}"; do
    unset "${__ref}"
  done
  _EA_REFS=()
  unset _EA_VARNAME
}
