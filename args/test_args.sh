#!/usr/bin/env bash

# Runs a call expected to abort. Written with `|| rc=$?` rather than a bare
# call because bt runs each test under set -e, where an unchecked non-zero
# would end the test before the assertion is reached.
expect_die() {
  local rc=0
  ("$@") >/dev/null 2>&1 || rc="$?"
  [[ "${rc}" -eq 253 ]]
}

mock_reference_variables() {
  _ea_create_reference_variable "param"
  _ea_create_reference_variable "flag;flag"
  _ea_create_reference_variable "array;index"
  _ea_create_reference_variable "collection;list"
}

test_extract() {
  local param flag dashed_arg port
  local -a array inc mount_path

  EXTRACTABLE_ARGS=(
    "param"
    "flag;flag"
    "array;index"
    "dashed-arg;flag"
  )

  args::extract \
    --param normal \
    --flag \
    --dashed-arg \
    --array0 array-element0 \
    --array1=array-element1 \
    non-arg1 non-arg2

  [[ "${param}" == "normal" ]] || ${report_failed} "param=${param}"
  [[ "${flag}" == true ]] || ${report_failed} "flag=${flag}"
  [[ "${dashed_arg}" == true ]] || ${report_failed} "dashed_arg=${dashed_arg}"
  [[ "${array[0]}" == "array-element0" ]] || ${report_failed} "array[0]=${array[0]}"
  [[ "${array[1]}" == "array-element1" ]] || ${report_failed} "array[1]=${array[1]}"
  [[ "${#array[@]}" -eq 2 ]] || ${report_failed} "array size=${#array[@]}"
  [[ "${#args[@]}" -eq 2 ]] || ${report_failed} "args size=${#args[@]}"
  [[ "${args[0]}" == "non-arg1" ]] || ${report_failed} "args[0]=${args[0]}"
  [[ "${args[1]}" == "non-arg2" ]] || ${report_failed} "args[1]=${args[1]}"

  # internal state does not survive the call
  [[ -z "${ref_param:-}" ]] || ${report_failed} "ref_param leaked"
  [[ -z "${i_array:-}" ]] || ${report_failed} "i_array leaked"

  # ── list args: dense, in encounter order, reset per parse
  EXTRACTABLE_ARGS=("inc;list" "mount-path;list")
  args::extract --inc /a --inc=/b --inc /c --mount-path /srv
  [[ "${#inc[@]}" -eq 3 ]] || ${report_failed} "inc size=${#inc[@]}"
  [[ "${inc[0]}" == "/a" ]] || ${report_failed} "inc[0]=${inc[0]}"
  [[ "${inc[2]}" == "/c" ]] || ${report_failed} "inc[2]=${inc[2]}"
  [[ "${mount_path[0]}" == "/srv" ]] || ${report_failed} "mount_path[0]=${mount_path[0]}"

  EXTRACTABLE_ARGS=("inc;list")
  args::extract --inc /only
  [[ "${#inc[@]}" -eq 1 ]] || ${report_failed} "list not reset between parses"

  EXTRACTABLE_ARGS=("inc;list")
  args::extract
  [[ "${#inc[@]}" -eq 0 ]] || ${report_failed} "empty list should be an empty array"

  # ── index args: caller-declared slots, order-independent and sparse
  EXTRACTABLE_ARGS=("array;index")
  unset array
  args::extract --array3 c --array1 a --array2 b
  [[ "${array[1]}" == "a" ]] || ${report_failed} "array[1]=${array[1]}"
  [[ "${array[3]}" == "c" ]] || ${report_failed} "array[3]=${array[3]}"

  EXTRACTABLE_ARGS=("array;index")
  unset array
  args::extract --array1 a --array5 e
  [[ "${#array[@]}" -eq 2 ]] || ${report_failed} "sparse size=${#array[@]}"
  [[ "${array[5]}" == "e" ]] || ${report_failed} "array[5]=${array[5]}"
  [[ -z "${array[2]:-}" ]] || ${report_failed} "array[2] should be unset"

  # ── value integrity: assigned, not read -- whitespace survives
  EXTRACTABLE_ARGS=("param" "inc;list")
  args::extract --param "  spaced  " --inc "  a b  " --inc c "two words"
  [[ "${param}" == "  spaced  " ]] || ${report_failed} "param=[${param}]"
  [[ "${inc[0]}" == "  a b  " ]] || ${report_failed} "inc[0]=[${inc[0]}]"
  [[ "${#args[@]}" -eq 1 ]] || ${report_failed} "positional re-split: ${#args[@]}"
  [[ "${args[0]}" == "two words" ]] || ${report_failed} "args[0]=[${args[0]}]"

  # ── option syntax
  EXTRACTABLE_ARGS=("port")
  args::extract --port -5
  [[ "${port}" == "-5" ]] || ${report_failed} "single dash treated as option: ${port}"

  EXTRACTABLE_ARGS=("param")
  args::extract --param v -- --not-an-option extra
  [[ "${#args[@]}" -eq 2 ]] || ${report_failed} "-- did not end options"
  [[ "${args[0]}" == "--not-an-option" ]] || ${report_failed} "args[0]=${args[0]}"

  EXTRACTABLE_ARGS=("param")
  expect_die args::extract --param v -x ||
    ${report_failed} "short option should be rejected"

  EXTRACTABLE_ARGS=()
  args::extract --anything || ${report_failed} "empty spec should be a no-op"

  # ── errors
  EXTRACTABLE_ARGS=("flag;flag")
  expect_die args::extract --flag=maybe ||
    ${report_failed} "flag given a value should abort"

  EXTRACTABLE_ARGS=("param")
  expect_die args::extract --bogus v ||
    ${report_failed} "undeclared arg should abort"

  EXTRACTABLE_ARGS=("param")
  expect_die args::extract --param2 v ||
    ${report_failed} "numbered arg on a non-index should abort"

  EXTRACTABLE_ARGS=("PATH")
  expect_die args::extract --PATH /nope ||
    ${report_failed} "reserved name should abort"
  [[ "${PATH}" != "/nope" ]] || ${report_failed} "PATH was overwritten"

  # ── required args are module state and must not leak between parses
  EXTRACTABLE_ARGS=("param;required")
  args::extract --param 1
  EXTRACTABLE_ARGS=("port")
  args::extract --port 2 ||
    ${report_failed} "second parse inherited the first spec's required args"

  return "${TEST_RESULT}"
}

# ── declaration ───────────────────────────────────────────────────────────────

test_ea_create_reference_variable() {
  mock_reference_variables

  [[ "${ref_param}" -eq 0 ]] || ${report_failed} "ref_param=${ref_param}"
  [[ "${ref_flag}" == "flaggable" ]] || ${report_failed} "ref_flag=${ref_flag}"
  [[ "${i_array}" == "index" ]] || ${report_failed} "i_array=${i_array}"
  [[ "${l_collection}" == "list" ]] || ${report_failed} "l_collection=${l_collection}"

  # a list also gets a slot counter, and its array starts empty
  [[ "${n_collection}" -eq 0 ]] || ${report_failed} "n_collection=${n_collection}"
  [[ "${#collection[@]}" -eq 0 ]] || ${report_failed} "collection not initialised empty"

  # dashes are normalised in every reference key, not only ref_*
  _ea_create_reference_variable "dashed-index;index"
  [[ "${i_dashed_index}" == "index" ]] || ${report_failed} "i_dashed_index=${i_dashed_index:-}"
  _ea_create_reference_variable "dashed-list;list"
  [[ "${l_dashed_list}" == "list" ]] || ${report_failed} "l_dashed_list=${l_dashed_list:-}"

  # unknown tag, and two type tags on one argument
  expect_die _ea_create_reference_variable "other;bogus" ||
    ${report_failed} "unknown tag should abort"
  expect_die _ea_create_reference_variable "other;list;flag" ||
    ${report_failed} "conflicting type tags should abort"

  # a name already declared cannot be declared again
  expect_die _ea_create_reference_variable "param;list" ||
    ${report_failed} "duplicate declaration should abort"

  return "${TEST_RESULT}"
}

test_ea_define_reference_variables() {
  # duplicates, in any combination of tags
  EXTRACTABLE_ARGS=("tag;list" "tag;index")
  expect_die _ea_define_reference_variables || ${report_failed} "list+index duplicate"

  EXTRACTABLE_ARGS=("port" "port")
  expect_die _ea_define_reference_variables || ${report_failed} "exact duplicate"

  # dash and underscore spellings collapse to the same variable name
  EXTRACTABLE_ARGS=("my-tag" "my_tag")
  expect_die _ea_define_reference_variables || ${report_failed} "dash/underscore alias"

  # a name ending in digits is unreachable when an index claims its base,
  # whichever order they are declared in
  EXTRACTABLE_ARGS=("tag;index" "tag1")
  expect_die _ea_define_reference_variables || ${report_failed} "index shadows tag1"

  EXTRACTABLE_ARGS=("tag1" "tag;index")
  expect_die _ea_define_reference_variables || ${report_failed} "shadowing, reverse order"

  # REQUIRED_ARGS is reset per call, not accumulated
  EXTRACTABLE_ARGS=("alpha;required")
  _ea_define_reference_variables
  [[ "${#REQUIRED_ARGS[@]}" -eq 1 ]] || ${report_failed} "REQUIRED_ARGS=${REQUIRED_ARGS[*]}"
  unset ref_alpha

  EXTRACTABLE_ARGS=("beta")
  _ea_define_reference_variables
  [[ "${#REQUIRED_ARGS[@]}" -eq 0 ]] || ${report_failed} "REQUIRED_ARGS not reset"

  return "${TEST_RESULT}"
}

test_ea_declared() {
  _ea_declared "nothing" && ${report_failed} "undeclared name reported as declared"

  _ea_create_reference_variable "plain"
  _ea_declared "plain" || ${report_failed} "ref_ not detected"

  _ea_create_reference_variable "idx;index"
  _ea_declared "idx" || ${report_failed} "i_ not detected"

  _ea_create_reference_variable "lst;list"
  _ea_declared "lst" || ${report_failed} "l_ not detected"

  return "${TEST_RESULT}"
}

test_ea_define_arg_value() {
  _ea_create_reference_variable "param"
  _ea_create_reference_variable "flag;flag"
  _ea_create_reference_variable "array;index"
  _ea_create_reference_variable "collection;list"

  _ea_define_arg_value "param"
  [[ "${_EA_VARNAME}" == "param" ]] || ${report_failed} "plain -> ${_EA_VARNAME}"

  _ea_define_arg_value "flag"
  [[ "${_EA_VARNAME}" == "flaggable" ]] || ${report_failed} "flag -> ${_EA_VARNAME}"

  _ea_define_arg_value "array3"
  [[ "${_EA_VARNAME}" == "array[3]" ]] || ${report_failed} "index -> ${_EA_VARNAME}"

  # a list takes the next free slot and advances its counter
  _ea_define_arg_value "collection"
  [[ "${_EA_VARNAME}" == "collection[0]" ]] || ${report_failed} "list -> ${_EA_VARNAME}"
  _ea_define_arg_value "collection"
  [[ "${_EA_VARNAME}" == "collection[1]" ]] || ${report_failed} "list -> ${_EA_VARNAME}"
  [[ "${n_collection}" -eq 2 ]] || ${report_failed} "n_collection=${n_collection}"

  expect_die _ea_define_arg_value "unknown" || ${report_failed} "unknown arg should abort"
  expect_die _ea_define_arg_value "param7" || ${report_failed} "type mismatch should abort"

  return "${TEST_RESULT}"
}

test_ea_create_var() {
  local param flag
  local -a array

  _ea_create_reference_variable "param"
  _ea_create_reference_variable "flag;flag"
  _ea_create_reference_variable "array;index"

  _ea_create_var "param" "value"
  [[ "${param}" == "value" ]] || ${report_failed} "param=${param}"

  _ea_create_var "flag" "true"
  [[ "${flag}" == "true" ]] || ${report_failed} "flag=${flag}"

  _ea_create_var "array2" "third"
  [[ "${array[2]}" == "third" ]] || ${report_failed} "array[2]=${array[2]}"

  expect_die _ea_create_var "flag" "maybe" ||
    ${report_failed} "non-boolean value for a flag should abort"

  return "${TEST_RESULT}"
}

# ── assignment and validation ─────────────────────────────────────────────────

test_ea_assign() {
  local target
  local -a slots

  _ea_assign "target" "plain"
  [[ "${target}" == "plain" ]] || ${report_failed} "target=${target}"

  # whitespace and newlines survive, unlike read -r <<<
  _ea_assign "target" "  padded  "
  [[ "${target}" == "  padded  " ]] || ${report_failed} "target=[${target}]"

  _ea_assign "target" "$(printf 'a\nb')"
  [[ "${target}" == "$(printf 'a\nb')" ]] || ${report_failed} "newline truncated"

  # array element targets are accepted
  _ea_assign "slots[1]" "second"
  [[ "${slots[1]}" == "second" ]] || ${report_failed} "slots[1]=${slots[1]}"

  # names are validated before they reach eval
  expect_die _ea_assign "PATH" "/nope" || ${report_failed} "reserved name accepted"
  [[ "${PATH}" != "/nope" ]] || ${report_failed} "PATH was overwritten"
  expect_die _ea_assign "bad-name" "x" || ${report_failed} "invalid identifier accepted"
  expect_die _ea_assign "" "x" || ${report_failed} "empty name accepted"

  return "${TEST_RESULT}"
}

test_ea_is_identifier() {
  _ea_is_identifier "name" || ${report_failed} "name rejected"
  _ea_is_identifier "_leading" || ${report_failed} "_leading rejected"
  _ea_is_identifier "with_digits9" || ${report_failed} "with_digits9 rejected"

  _ea_is_identifier "" && ${report_failed} "empty accepted"
  _ea_is_identifier "9leading" && ${report_failed} "leading digit accepted"
  _ea_is_identifier "with-dash" && ${report_failed} "dash accepted"
  _ea_is_identifier 'sneaky;rm' && ${report_failed} "metacharacter accepted"
  _ea_is_identifier "PATH" && ${report_failed} "PATH accepted"
  _ea_is_identifier "IFS" && ${report_failed} "IFS accepted"
  _ea_is_identifier "BASH_VERSION" && ${report_failed} "BASH_VERSION accepted"

  return "${TEST_RESULT}"
}

test_ea_is_number() {
  _ea_is_number "0" || ${report_failed} "0 rejected"
  _ea_is_number "42" || ${report_failed} "42 rejected"

  _ea_is_number "" && ${report_failed} "empty accepted"
  _ea_is_number "1a" && ${report_failed} "1a accepted"
  _ea_is_number "-1" && ${report_failed} "-1 accepted"
  _ea_is_number " 1" && ${report_failed} "leading space accepted"

  return "${TEST_RESULT}"
}

# ── required arguments ────────────────────────────────────────────────────────

test_ea_check_required_args() {
  _ea_create_reference_variable "param;required"
  _ea_create_reference_variable "param-flag;flag;required"
  _ea_create_reference_variable "param2"

  # One element per argument. The old implementation re-split its input on
  # IFS, so a single "param param-flag" string happened to work; it now
  # compares elements directly and that form no longer matches.
  local args1=("param" "param-flag")
  local args2=("arg" "param2")

  _ea_check_required_args "${args1[@]}" || ${report_failed} "required args not satisfied"
  expect_die _ea_check_required_args "${args2[@]}" ||
    ${report_failed} "missing required arg should abort"

  return "${TEST_RESULT}"
}

test_ea_contains() {
  _ea_contains "b" "a" "b" "c" || ${report_failed} "present value not found"
  _ea_contains "a" "a" || ${report_failed} "single element not found"
  _ea_contains "two words" "one" "two words" || ${report_failed} "spaced element not found"

  _ea_contains "z" "a" "b" && ${report_failed} "absent value found"
  _ea_contains "b" && ${report_failed} "found something in an empty list"
  _ea_contains "two" "one" "two words" && ${report_failed} "matched a substring"

  return "${TEST_RESULT}"
}

# ── failure path ──────────────────────────────────────────────────────────────

test_ea_die() {
  local rc=0
  (_ea_die "boom") >/dev/null 2>&1 || rc="$?"
  [[ "${rc}" -eq 253 ]] || ${report_failed} "exit status=${rc}, expected 253"

  # both lines go to stderr; nothing lands on stdout
  local out err
  out="$( (_ea_die "boom") 2>/dev/null || true)"
  [[ -z "${out}" ]] || ${report_failed} "wrote to stdout: ${out}"

  err="$( (_ea_die "boom") 2>&1 >/dev/null || true)"
  case "${err}" in
  *'[ERROR] boom.'*) : ;;
  *) ${report_failed} "stderr=${err}" ;;
  esac

  return "${TEST_RESULT}"
}
