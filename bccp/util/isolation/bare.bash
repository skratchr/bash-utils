################################################################################
# isolation/bare.bash
#
# Provider: bare host
#
# Runs test commands directly on the host in a temporary workspace. Useful for
# fast local iteration where environment isolation is not required.
#
# Usage:
#   source isolation/bare.bash
#
# Environment (consumed on source):
#   repo_name     - repository name; used as a label in workspace paths
#   git_sha       - commit SHA; combined with git_branch to name the workspace
#   git_branch    - branch name; used as a prefix in the workspace directory
#   project_root  - repository root; workspace is created under $project_root/ci/
#   CI_HOME       - (optional) override workspace root, e.g. in a CI environment
#
# Exports:
#   test_workspace - path to the temporary working directory for this run
#
# Provider interface (all exported):
#   provider_run     - no-op; workspace is created at source time
#   provider_exec    - executes a bash command on the host; pauses on failure
#                      in interactive sessions to allow inspection
#   provider_stop    - no-op
#   provider_remove  - no-op
#   provider_cleanup - removes test_workspace
#
# Notes:
#   - provider_exec pauses and waits for a keypress on non-zero exit. This is
#     intentional for local debugging and should be acceptable in non-CI use.
#   - The broken export -f aliases (run_environment etc.) are a known issue and
#     should be fixed to export -f provider_run etc. for consistency.
################################################################################

provider_run() { :; }
export -f provider_run

provider_stop() { :; }
export -f provider_stop

provider_remove() { :; }
export -f provider_remove

provider_cleanup() { rm -rf "${test_workspace:?##*/}" "${guest_workspace}"; }
export -f provider_cleanup

provider_exec() {
	bash "$@"
	local rc=$?
	if [[ "${rc}" != 0 ]]; then
		echo "failed execution, debug as you wish, press a key to continue..."
		read -n 1 -s -r
		exit $rc
	fi
}
export -f provider_exec

if [[ -n "${CI_HOME+x}" ]] && [[ -d "${CI_HOME:-}" ]]; then
	test_workspace=$(mktemp -d "${CI_HOME}/${git_branch}.${git_sha}.XXXXXX")
else
	test_workspace=$(mktemp -d "${project_root}/ci/${git_branch}.${git_sha}.XXXXXX")
fi
export test_workspace
readonly test_workspace
