#!/usr/bin/env bash
################################################################################
# isolation/tart.bash
#
# Provider: Tart VM (macOS, Apple Silicon)
#
# Runs test commands inside a per-run Tart virtual machine cloned from a
# pre-existing base image. The base VM must exist before sourcing this file.
#
# Usage:
#   source isolation/tart.bash
#
# Prerequisites:
#   A Tart VM named "${repo_name}.base" must exist locally. Build or pull it
#   once before running tests.
#
# Environment (consumed on source):
#   repo_name        - used to derive the base VM name (${repo_name}.base)
#                      and per-run VM name (${repo_name}.${git_sha})
#   git_sha          - commit SHA; used to name the VM and workspace
#   git_branch       - branch name; used as prefix in the workspace directory
#   project_root     - repository root; workspace created under $project_root/ci/
#   CI_HOME          - (optional) override workspace root
#   artifacts_dir    - path to the artefacts directory; mounted into the VM
#   guest_mount_root - mount point inside the guest for the virtiofs share;
#                      the default macOS share at "/Volumes/My Shared Files" is
#                      unmounted and replaced at this path
#
# Exports:
#   test_workspace - path to the temporary working directory for this run
#   test_vm        - name of the Tart VM for this run
#
# Provider interface:
#   provider_run     - clone base VM, start it, wait for tart-guest-agent IP,
#                      then remount the virtiofs share at guest_mount_root
#   provider_exec    - run a bash --login command inside the VM via tart exec;
#                      output captured via script(1) to $OUTPUT (default /dev/null)
#   provider_stop    - stop the VM with a configurable timeout (default 60s)
#   provider_remove  - force-stop (1s) and delete the VM
#   provider_cleanup - delete VM if stopped successfully, then delete test_workspace
#
# Notes:
#   - tart run is backgrounded since it blocks; provider_run then polls for
#     an IP address via tart-guest-agent before proceeding.
#   - provider_exec uses script(1) rather than direct exec because tart exec
#     does not support a TTY-less mode; script provides the expected behaviour.
#   - provider_cleanup only deletes the VM if provider_stop succeeds (unlike
#     the other providers which force-delete regardless).
################################################################################

#
# helpers
#

_vm_exists() {
	tart get "${1:?"Missing argument vm_name"}" &>/dev/null
}

_vm_state() {
	tart get "${1:?"Missing argument vm_name"}" 2>/dev/null | tail -n 1 | awk '{ print $NF }'
}

#
# provider interface
#

provider_run() {
	local max_attempts=10
	readonly max_attempts
	local attempt=1

	echo ""
	echo "Starting VM '${test_vm}'..."
	echo ""

	while true; do
		if ! _vm_exists "${test_vm}"; then
			tart clone "${base_vm}" "${test_vm}"
		fi

		if [[ "$(_vm_state "${test_vm}")" != "running" ]]; then
			tart run \
				--dir="${test_workspace##*/}:${test_workspace}" \
				--dir="artifacts:${artifacts_dir}" \
				"${test_vm}" &
		fi

		echo "Waiting for IP from tart-guest-agent..."
		if tart ip "${test_vm}" --wait 30 --resolver agent >/dev/null; then
			break
		fi

		if [[ "${attempt}" -ge "${max_attempts}" ]]; then
			echo "Could not verify IP address, max attempts exceeded (${attempt}), script exiting..."
			exit 1
		else
			echo "Could not verify IP address, retrying (${attempt})..."
			provider_stop
		fi
		attempt=$((attempt + 1))
	done

	echo "Unmounting default dir..."
	provider_exec "sudo umount \"/Volumes/My Shared Files\""

	echo "Remounting to ${guest_mount_root}"
	provider_exec "sudo mkdir -p \"${guest_mount_root}\""
	provider_exec "sudo mount_virtiofs com.apple.virtio-fs.automount \"${guest_mount_root}\""
}

provider_exec() {
	local output="${OUTPUT:-"/dev/null"}"
	readonly output

	if ! script -q "${output}" tart exec "${test_vm}" /usr/bin/env bash --login -c "${@}"; then
		if [[ "${output}" != "/dev/null" && -f "${output}" ]]; then
			echo "Script failed"
			cat "${output}"
			exit 1
		fi
	fi
}

provider_stop() {
	local timeout="${1:-60}"
	readonly timeout

	if [[ "$(_vm_state "${test_vm}")" != "stopped" ]]; then
		if ! tart stop -t "${timeout}" "${test_vm}"; then
			echo "could not stop vm '${test_vm}'"
			return 1
		fi
	fi
}

provider_remove() {
	# timeout is set to 1 to force the environment to be destroyed right away
	provider_stop 1 || :
	tart delete "${test_vm}"
}

provider_cleanup() {
	set +u
	if [[ -n "${test_vm}" ]]; then
		if _vm_exists "${test_vm}" && provider_stop 1; then
			tart delete "${test_vm}"
		fi
	fi
	rm -rf "${test_workspace}"
}

#
# provider specific setup
#

readonly base_vm="${repo_name}.base"
if ! _vm_exists "${base_vm}"; then
	echo "Could not find base image used for testing..." >&2
	echo "Please run 'build_base_image.sh' and try again." >&2
	exit 1
fi

export test_vm="${repo_name}.${git_sha}"
readonly test_vm

if ! _vm_exists "${test_vm}"; then
	if [[ -n "${CI_HOME+x}" ]] && [[ -d "${CI_HOME:-}" ]]; then
		test_workspace=$(mktemp -d "${CI_HOME}/${git_branch}.${git_sha}.XXXXXX")
	else
		test_workspace=$(mktemp -d "${project_root}/ci/${git_branch}.${git_sha}.XXXXXX")
	fi
else
	if [[ -n "${CI_HOME+x}" ]] && [[ -d "${CI_HOME:-}" ]]; then
		workspaces=("${CI_HOME}/${git_branch}.${git_sha}".*)
		test_workspace="${workspaces[0]}"
	else
		workspaces=("${project_root}/ci/${git_branch}.${git_sha}".*)
		test_workspace="${workspaces[0]}"
	fi
fi
export test_workspace
readonly test_workspace
