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
