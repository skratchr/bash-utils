#!/usr/bin/env bash
#
# Strategy: stub out tmux and git so no live server is needed.
# Plan-builder tests inspect the PLAN_* arrays directly.
# diff_plan tests control session_exists / window_exists via the tmux stub.

# Tracks calls made to tmux for assertion in apply tests.
declare -a TMUX_CALLS=()

tmux() {
  TMUX_CALLS+=("$*")
  case "${1}" in
  has-session)
    # Return 1 (session does not exist) unless overridden per-test.
    return "${STUB_SESSION_EXISTS:-1}"
    ;;
  list-windows)
    # Return nothing (no windows) unless overridden per-test.
    echo "${STUB_LIST_WINDOWS:-}"
    ;;
  list-panes)
    echo "${STUB_LIST_PANES:-1}"
    ;;
  display-message)
    echo "${STUB_DISPLAY_MESSAGE:-}"
    ;;
  list-sessions)
    echo "${STUB_LIST_SESSIONS:-}"
    ;;
  *)
    return 0
    ;;
  esac
}

git() {
  TMUX_CALLS+=("git $*")
  return 0
}

_reset_plan() {
  PLAN_PANES=()
  PLAN_CMDS=()
  PLAN_OPTS=()
  PLAN_URLS=()
  PLAN_DIRS=()
  PLAN_ORDER=()
  SESSION_ORDER=()
  ACTIONS=()
  ACTION_MAP=()
  TMUX_CALLS=()
  STUB_SESSION_EXISTS=1
  STUB_LIST_WINDOWS=
  STUB_LIST_PANES=1
}

test_plan_session() {
  _reset_plan
  plan_session "myapp"
  [[ "${#SESSION_ORDER[@]}" -eq 1 ]] || $report_failed "expected 1 session, got ${#SESSION_ORDER[@]}"
  [[ "${SESSION_ORDER[0]}" == "myapp" ]] || $report_failed "expected myapp, got ${SESSION_ORDER[0]}"

  plan_session "myapp"
  [[ "${#SESSION_ORDER[@]}" -eq 1 ]] || $report_failed "duplicate should not be added"

  plan_session "other"
  [[ "${#SESSION_ORDER[@]}" -eq 2 ]] || $report_failed "expected 2 sessions, got ${#SESSION_ORDER[@]}"

  return $TEST_RESULT
}

test_plan_window() {
  local test_table=(
    # "session:window|pane_count|cmd_at_0"
    "myapp:code|1|cd '/src/myapp'"
    "myapp:debg|2|cd '/src/myapp'"
    "logs:syslog|1|tail -f /var/log/syslog"
  )

  local entry key panes cmd0
  for entry in "${test_table[@]}"; do
    _reset_plan
    IFS='|' read -r key panes cmd0 <<< "${entry}"
    local session="${key%%:*}"
    local window="${key#*:}"

    if [[ "${panes}" -eq 1 ]]; then
      plan_window "${session}" "${window}" "${cmd0}"
    else
      plan_window "${session}" "${window}" "${cmd0}" "${cmd0}"
    fi

    [[ "${PLAN_PANES[${key}]}" -eq "${panes}" ]] \
      || $report_failed "${key}: expected ${panes} panes, got ${PLAN_PANES[${key}]}"
    [[ "${PLAN_CMDS[${key}:0]}" == "${cmd0}" ]] \
      || $report_failed "${key}: expected cmd '${cmd0}', got '${PLAN_CMDS[${key}:0]}'"
    [[ "${PLAN_ORDER[-1]}" == "${key}" ]] \
      || $report_failed "${key}: not last in PLAN_ORDER"
  done

  return $TEST_RESULT
}

test_plan_window_opt() {
  _reset_plan
  plan_window "llm" "claude" "claude"
  plan_window_opt "llm" "claude" "remain-on-exit=on"

  [[ "${PLAN_OPTS[llm:claude]}" == *"remain-on-exit=on"* ]] \
    || $report_failed "option not recorded: ${PLAN_OPTS[llm:claude]:-<empty>}"

  plan_window_opt "llm" "claude" "other-opt=yes"
  [[ "${PLAN_OPTS[llm:claude]}" == *"other-opt=yes"* ]] \
    || $report_failed "second option not appended: ${PLAN_OPTS[llm:claude]}"
  [[ "${PLAN_OPTS[llm:claude]}" == *"remain-on-exit=on"* ]] \
    || $report_failed "first option lost after second append"

  return $TEST_RESULT
}

test_plan_project_sessions() {
  _reset_plan

  declare -a project_code=("myapp" "other")
  declare -a project_dirs=("/src/myapp" "/src/other")
  declare -a project_urls=("https://github.com/x/myapp" "")
  declare -a project_debg=("2" "")
  declare -a project_logs=("tail -f /var/log/a|tail -f /var/log/b" "")

  plan_project_sessions

  # code windows created for both projects
  [[ -n "${PLAN_PANES[myapp:code]:-}" ]] \
    || $report_failed "myapp:code not planned"
  [[ -n "${PLAN_PANES[other:code]:-}" ]] \
    || $report_failed "other:code not planned"

  # debg window only for myapp (project_debg[1] is empty)
  [[ -n "${PLAN_PANES[myapp:debg]:-}" ]] \
    || $report_failed "myapp:debg not planned"
  [[ -z "${PLAN_PANES[other:debg]:-}" ]] \
    || $report_failed "other:debg should not be planned"

  # logs window only for myapp
  [[ -n "${PLAN_PANES[myapp:logs]:-}" ]] \
    || $report_failed "myapp:logs not planned"
  [[ "${PLAN_PANES[myapp:logs]}" -eq 2 ]] \
    || $report_failed "myapp:logs expected 2 panes, got ${PLAN_PANES[myapp:logs]}"

  # URL and dir recorded
  [[ "${PLAN_URLS[myapp:code]}" == "https://github.com/x/myapp" ]] \
    || $report_failed "myapp:code URL not recorded"
  [[ "${PLAN_DIRS[myapp:code]}" == "/src/myapp" ]] \
    || $report_failed "myapp:code dir not recorded"

  return $TEST_RESULT
}

test_plan_logs_session() {
  _reset_plan

  # Empty — should be a no-op
  unified_logs=()
  plan_logs_session
  [[ "${#PLAN_ORDER[@]}" -eq 0 ]] \
    || $report_failed "empty unified_logs should produce no plan entries"

  _reset_plan
  declare -A unified_logs=(["syslog"]="tail -f /var/log/syslog")
  plan_logs_session

  [[ -n "${PLAN_PANES[logs:syslog]:-}" ]] \
    || $report_failed "logs:syslog not planned"

  return $TEST_RESULT
}

test_plan_ssh_session() {
  _reset_plan
  sshs=()
  plan_ssh_session
  [[ "${#PLAN_ORDER[@]}" -eq 0 ]] \
    || $report_failed "empty sshs should produce no plan entries"

  _reset_plan
  sshs=("homelab" "pi")
  plan_ssh_session

  [[ -n "${PLAN_PANES[ssh:homelab]:-}" ]] \
    || $report_failed "ssh:homelab not planned"
  [[ "${PLAN_CMDS[ssh:homelab:0]}" == "ssh homelab" ]] \
    || $report_failed "wrong cmd for ssh:homelab: ${PLAN_CMDS[ssh:homelab:0]:-<empty>}"
  [[ -n "${PLAN_PANES[ssh:pi]:-}" ]] \
    || $report_failed "ssh:pi not planned"

  return $TEST_RESULT
}

test_diff_plan() {
  _reset_plan
  plan_window "myapp" "code" "cd /src"
  plan_window "myapp" "debg" "cd /src"

  # Case 1: session and windows do not exist → CREATE actions
  STUB_SESSION_EXISTS=1  # has-session returns 1 (does not exist)
  STUB_LIST_WINDOWS=     # list-windows returns nothing
  diff_plan

  [[ "${ACTIONS[0]}" == "CREATE_SESSION myapp" ]] \
    || $report_failed "expected CREATE_SESSION, got: ${ACTIONS[0]:-<empty>}"
  [[ "${ACTIONS[1]}" == "CREATE_WINDOW myapp:code" ]] \
    || $report_failed "expected CREATE_WINDOW myapp:code, got: ${ACTIONS[1]:-<empty>}"
  [[ "${ACTIONS[2]}" == "CREATE_WINDOW myapp:debg" ]] \
    || $report_failed "expected CREATE_WINDOW myapp:debg, got: ${ACTIONS[2]:-<empty>}"

  # Case 2: session exists, windows exist with correct pane count → SKIP
  _reset_plan
  plan_window "myapp" "code" "cd /src"
  STUB_SESSION_EXISTS=0          # session exists
  STUB_LIST_WINDOWS="code"       # window exists
  STUB_LIST_PANES=1              # pane count matches plan (1 pane)
  diff_plan

  [[ "${ACTIONS[0]}" == "SKIP_SESSION myapp" ]] \
    || $report_failed "expected SKIP_SESSION, got: ${ACTIONS[0]:-<empty>}"
  [[ "${ACTION_MAP[myapp:code]}" == "SKIP_WINDOW" ]] \
    || $report_failed "expected SKIP_WINDOW, got: ${ACTION_MAP[myapp:code]:-<empty>}"

  # Case 3: session exists, window exists but pane count differs → REBUILD
  _reset_plan
  plan_window "myapp" "code" "cd /src" "cd /src"  # 2 panes planned
  STUB_SESSION_EXISTS=0
  STUB_LIST_WINDOWS="code"
  STUB_LIST_PANES=1              # only 1 pane live → mismatch
  diff_plan

  [[ "${ACTION_MAP[myapp:code]}" == "REBUILD_WINDOW" ]] \
    || $report_failed "expected REBUILD_WINDOW, got: ${ACTION_MAP[myapp:code]:-<empty>}"

  return $TEST_RESULT
}

test_report() {
  _reset_plan
  plan_window "myapp" "code" "cd /src"
  plan_window "myapp" "debg" "cd /src" "cd /src"

  ACTIONS=(
    "CREATE_SESSION myapp"
    "CREATE_WINDOW myapp:code"
    "SKIP_WINDOW myapp:debg"
  )

  local output
  output="$(report)"

  [[ "${output}" == *"[+] myapp"* ]] \
    || $report_failed "CREATE_SESSION not shown"
  [[ "${output}" == *"[+] code"* ]] \
    || $report_failed "CREATE_WINDOW not shown"
  [[ "${output}" == *"[~] debg"* ]] \
    || $report_failed "SKIP_WINDOW not shown"
  [[ "${output}" == *"created: 2"* ]] \
    || $report_failed "created count wrong: ${output}"

  return $TEST_RESULT
}
