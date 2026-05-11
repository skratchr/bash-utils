#!/usr/bin/env bash

# Source this file at the top of each test script, passing the group name:
#
#   source test_group.env "my-feature"
#
# Tests call pass() or fail() to report results, either inline or from
# subshells. Both patterns work identically:
#
#   some_command && pass || fail              # inline
#   ( some_command && pass || fail )          # subshell
#   ( source case.env "my-case"; ... )  # structured test case
#
# For structured test cases with isolation, timing, and filtering, source
# case.env inside a subshell. It calls pass()/fail() automatically
# on exit, so no explicit call is needed. Custom test case implementations
# are also supported — any script that calls pass() or fail() will integrate
# correctly with result aggregation.
#
# The group exits with code 0 if all tests passed, 1 if any failed.
#
# Exported functions: pass, fail, log_result, log_stderr
# Exported variables: group_name, group_shell, FD_RESULT_WRITE, FD_RESULT_READ
#
# Globals (set before sourcing):
#   ARTIFACTS_DIR — directory for result artifact files (default: /tmp)

# Disable exit-on-error. A failing test returns non-zero by design — that is
# not a shell error and must not terminate the runner. Error handling for
# genuinely fatal conditions (pipe setup, signal registration) is done
# explicitly with early-exit guards below.
set +e -Euo pipefail
# File descriptors used for result aggregation across subshells.
# Results are written to FD_RESULT_WRITE and drained from FD_RESULT_READ
# in the EXIT handler. FD_RESULT_WRITE is opened read+write to avoid
# blocking on open(), and is inherited by all subshells automatically.

_pipe_result() { echo "${1}" >&"${FD_RESULT_WRITE}"; }

log_result() { echo "$*" >>"${ARTIFACTS_DIR:-/tmp}/${group_name}.result"; }

log_stderr() { printf '%s\n' "$*" >&2; }

pass() { _pipe_result "pass"; }

fail() { _pipe_result "fail"; }

handle_signal() {
	local signal="${1?"Missing argument signal"}"
	readonly signal

	case "${signal}" in
	INT)
		trap - INT
		kill -INT "$$"
		;;
	TERM)
		trap - TERM
		kill -TERM "$$"
		;;
	ABRT)
		trap - ABRT
		kill -ABRT "$$"
		;;
	EXIT)
		# Close the write end of the result pipe. Once all subshells have
		# exited and their inherited copies of FD_RESULT_WRITE are closed,
		# the read loop below will terminate naturally on EOF — no sentinel
		# value needed.
		exec {FD_RESULT_WRITE}>&-
		while read -r _result <&"${FD_RESULT_READ}"; do
			case "${_result}" in
			pass) tests_passed=$((tests_passed + 1)) ;;
			fail) tests_failed=$((tests_failed + 1)) ;;
			esac
		done
		exec {FD_RESULT_READ}>&-
		rm -rf "${_result_pipe_dir}"
		echo ""
		echo "PASS: ${tests_passed}"
		echo "FAIL: ${tests_failed}"
		if [[ "${tests_failed}" -eq 0 ]]; then
			exit 0
		else
			exit 1
		fi
		;;
	esac
}

tests_passed=0
tests_failed=0

export group_shell="$$"
readonly group_shell

# Create a temporary directory to hold the result fifo. The directory is
# cleaned up in the EXIT handler.
_result_pipe_dir=$(mktemp -d)
readonly _result_pipe_dir

if ! mkfifo "${_result_pipe_dir}/results"; then
	echo "error: failed to create result fifo" >&2
	rm -rf "${_result_pipe_dir}"
	exit 1
fi

# Open the result pipe. bash's {var}<> syntax allocates the first available
# fd above 9 and assigns its number to the variable — no manual fd probing
# needed. FD_RESULT_WRITE is opened read+write (<>) so open(2) returns
# immediately without blocking for a reader. FD_RESULT_READ is opened
# read-only and used exclusively by the EXIT handler drain loop.
# Subshells inherit FD_RESULT_WRITE automatically — no explicit setup needed.
exec {FD_RESULT_WRITE}<>"${_result_pipe_dir}/results"
export FD_RESULT_WRITE
readonly FD_RESULT_WRITE

exec {FD_RESULT_READ}<"${_result_pipe_dir}/results"
export FD_RESULT_READ
readonly FD_RESULT_READ

# Set up signal handlers. Verify each trap was registered successfully — some
# terminals (e.g. those that internally use USR2) may silently ignore certain
# signals, which would cause results to be lost.
for s in INT TERM ABRT EXIT; do
	trap "handle_signal ${s}" "${s}"

	if ! trap -p "${s}" | grep -q handle_signal; then
		echo "Failed to setup signal handler for '${s}', check your terminal"
		echo "Script exiting..."
		kill -TERM "${group_shell}"
	fi
done

export -f _pipe_result
export -f log_result
export -f log_stderr
export -f pass
export -f fail

export group_name="${1:?"Missing argument group_name"}"
readonly group_name

rm -f "${ARTIFACTS_DIR:-/tmp}/${group_name}.result"
