#!/usr/bin/env bash

# Source this file at the top of each test case script, passing the case name:
#
#   source case.env "my-test-case"
#
# Each test case must run in its own subshell to prevent variable leakage
# and to allow the EXIT trap to fire independently per case:
#
#   ( source case.env "my-test-case"
#     some_command || $test_failed "reason"
#   )
#
# On exit the trap calls pass() or fail() automatically — no explicit call
# is needed. Use failed() or fatal() to exit early with a diagnostic message:
#
#   failed()  ends the case and reports FAIL; the group continues running.
#   fatal()   ends the case, reports FAIL, and kills the group via ABRT.
#
# Convenience aliases with automatic source location are exported as strings
# and invoked with eval:
#
#   $test_failed "reason"   # calls failed() with BASH_SOURCE:LINENO prefix
#   $test_fatal  "reason"   # calls fatal()  with BASH_SOURCE:LINENO prefix
#
# The case exits with code 0 if the test passed, 100 if it failed, 101 on a
# fatal error, 102/103 on skip (verbose/silent), and 130 on SIGINT.
#
# Exported variables (read from environment, set before sourcing):
#   verbose      — enables verbose log output (default: false)
#   indent       — enables tab-indented log output (default: false)
#   SKIP         — space-separated list of case names to skip silently
#   FILTER       — space-separated list of case names to run; all others are skipped
#   LIST_CASE    — when set to "true", prints the case name and exits (default: false)
#
# Required environment (inherited from group.env):
#   group_name   — name of the parent test group
#   group_shell  — PID of the group shell; used to validate subshell execution
#                  and to propagate fatal errors via kill -ABRT
#   FD_RESULT_WRITE, FD_RESULT_READ, pass(), fail(), log_result(), log_stderr()
#
# Arguments:
#   $1  — test case name (required)
#   $2  — test group name override (optional, defaults to $group_name)

set -eE

# Save and restore stdout/stderr around indent redirection.
# These fds are allocated by bash automatically via {var} syntax when
# stdio_indent_redirect runs; they are declared here for documentation only.
FD_STDOUT_SAVE=
FD_STDERR_SAVE=

# Redirect stdout/stderr through a sed pipeline that prepends a tab to every
# line. Saves the original fds and filter PIDs so stdio_indent_restore can
# drain and undo the redirection. Disabled when indent_mode is false.
stdio_indent_redirect() {
	if [[ "${indent_mode}" == "false" ]]; then
		return 0
	fi

	exec {FD_STDOUT_SAVE}>&1 {FD_STDERR_SAVE}>&2

	exec 1> >(sed 's/^/\t/' >&"${FD_STDOUT_SAVE}")
	INDENT_STDOUT_PID=$!

	exec 2> >(sed 's/^/\t/' >&"${FD_STDERR_SAVE}")
	INDENT_STDERR_PID=$!
}

# Restore stdout/stderr to the saved fds and drain the sed filter processes.
# Restoring the fds closes the write ends of the pipes, sending EOF to sed.
# wait ensures all buffered output is flushed before the save fds are closed.
# Called in on_exit before any log output so result lines are never indented.
stdio_indent_restore() {
	if [[ "${indent_mode}" == "false" ]]; then
		return 0
	fi

	exec 1>&"${FD_STDOUT_SAVE}"
	exec 2>&"${FD_STDERR_SAVE}"

	wait "${INDENT_STDOUT_PID}" "${INDENT_STDERR_PID}" 2>/dev/null

	exec {FD_STDOUT_SAVE}>&-
	exec {FD_STDERR_SAVE}>&-
}

# Exit with the appropriate skip code.
# 102 = skip with output (verbose), 103 = skip silently.
_exit_skip() {
	if [[ "${verbose_mode}" == "true" ]]; then
		exit 102
	else
		exit 103
	fi
}

# Exit the test case with a FAIL result, logging an optional diagnostic message
# to stderr. The group continues running after this returns.
failed() {
	local src="${BASH_SOURCE[1]}"
	local line="${BASH_LINENO[0]}"
	local msg="${src}:${line} ${1}"
	shift

	if [[ $# -gt 0 ]]; then
		msg="${msg}: $*"
	fi
	log_stderr "${msg}"
	exit 100
}

# Exit the test case with a FAIL result and kill the group shell via ABRT,
# preventing any further test cases from running.
fatal() {
	local src="${BASH_SOURCE[1]}"
	local line="${BASH_LINENO[0]}"
	local msg="${src}:${line} ${1}"
	shift

	if [[ $# -gt 0 ]]; then
		msg="${msg}: $*"
	fi
	log_stderr "fatal error: ${msg}"
	exit 101
}

# Format the elapsed time since $test_start as a human-readable string
# (e.g. "1h2m3s", "45s", "0s").
duration() {
	local d=$((SECONDS - test_start))
	readonly d

	local h=$((d / 3600))
	readonly h

	local m=$(((d % 3600) / 60))
	readonly m

	local s=$((d % 60))
	readonly s

	local parts=()
	if [[ $h -gt 0 ]]; then parts+=("${h}h"); fi
	if [[ $m -gt 0 ]]; then parts+=("${m}m"); fi
	if [[ $s -gt 0 ]]; then parts+=("${s}s"); fi
	if [[ ${#parts[@]} -eq 0 ]]; then
		parts+=("0s")
	fi
	printf -v joined "%s" "${parts[@]}"
	echo "${joined}"
}

# EXIT trap. Inspects the exit code, writes the result to the log and the
# result pipe, and emits a summary line to stderr. Restores indented stdio
# before any output so result lines are never tab-prefixed.
#
# Exit code protocol:
#   0    — pass
#   100  — failed() called; report FAIL, group continues
#   101  — fatal() called; report FAIL, kill group via ABRT
#   102  — skip, verbose (log + print skip line)
#   103  — skip, silent (exit 0, no output)
#   130  — SIGINT received; restore stdio and kill process group
#   *    — unexpected non-zero; treat as fatal
on_exit() {
	local exit_code=$?
	readonly exit_code

	trap - ERR

	read -r duration < <(duration)
	readonly duration

	case "${exit_code}" in
	0) # success
		stdio_indent_restore
		log_result "${test_case},PASS"
		log_stderr "--- PASS ${test_name} (${duration})"
		pass
		;;
	100) # failed
		stdio_indent_restore
		log_result "${test_case},FAIL"
		log_stderr "--- FAIL ${test_name} (${duration})"
		fail
		;;
	101) # fatal — kill the group shell so no further cases run
		stdio_indent_restore
		log_result "${test_case},FAIL"
		kill -ABRT "${group_shell}" 2>/dev/null || :
		;;
	102) # skip (verbose)
		log_result "${test_case},SKIP"
		log_stderr "=== SKIP: ${test_name} (${duration})"
		;;
	103) # skip (silent)
		exit 0
		;;
	130) # SIGINT — restore stdio and propagate to process group
		stdio_indent_restore
		log_stderr "Test interrupted, exiting..." >&2
		kill -TERM -$$ 2>/dev/null || :
		;;
	*)
		stdio_indent_restore
		echo "Caught unexpected non-zero exit code: ${exit_code}" >&2
		log_result "${test_case},FAIL"
		log_stderr "--- FAIL ${test_name} (${duration})"
		kill -ABRT "${group_shell}" 2>/dev/null || :
		;;
	esac
}

trap 'exit 130' INT
trap 'exit $?' ERR
trap 'on_exit' EXIT

verbose_mode="${verbose:-false}"
readonly verbose_mode

indent_mode="${indent:-false}"
readonly indent_mode

test_case="${1:?"Missing argument test case"}"
readonly test_case

test_group="${2:-${group_name}}"
readonly test_group

test_name="${test_group}/${test_case}"
readonly test_name

test_start="${SECONDS}"
readonly test_start

# Convenience aliases that capture source location automatically.
# Usage: $test_failed "reason"  or  $test_fatal "reason"
declare -rx test_failed='failed'
declare -rx test_fatal='fatal'

if [[ -z "${group_shell}" ]]; then
	$test_failed "$test_name: no parent shell-environment exists"
fi

if [[ "${group_shell}" == "${BASHPID}" ]]; then
	$test_failed "$test_name: must run in a subshell"
fi

# just print the name of the test case
if [[ -n "${LIST_CASE+x}" && "${LIST_CASE}" == "true" ]]; then
	echo "${test_case}"
	exit 103
fi

if [[ -n "${SKIP+x}" ]]; then
	IFS=" " read -r -a skip <<<"${SKIP}"
	for item in "${skip[@]}"; do
		[[ "${item}" == "${test_case}" ]] && _exit_skip
	done
fi

if [[ -n "${FILTER+x}" ]]; then
	matched=false
	IFS=" " read -r -a filter <<<"${FILTER}"
	for item in "${filter[@]}"; do
		if [[ "${item}" == "${test_case}" ]]; then
			matched=true
			break
		fi
	done

	if [[ "${matched}" != "true" ]]; then
		_exit_skip
	fi
fi

log_stderr "=== RUN ${test_name}"
stdio_indent_redirect
