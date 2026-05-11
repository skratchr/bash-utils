#!/usr/bin/env bash
################################################################################
# isolation/docker.bash
#
# Provider: Docker container
#
# Runs test commands inside a per-run Docker container derived from a pre-built
# base image. The base image must exist before sourcing this file.
#
# Usage:
#   source isolation/docker.bash
#
# Prerequisites:
#   A base image named "${repo_name}.base" must exist locally. Build it with
#   your project's build_base_image.sh (or equivalent) before sourcing this.
#
# Environment (consumed on source):
#   repo_name     - used to derive the base image name (${repo_name}.base)
#                   and per-run container name (${repo_name}.${git_sha})
#   git_sha       - commit SHA; used to name the container and workspace
#   git_branch    - branch name; used as a prefix in the workspace directory
#   project_root  - repository root; workspace created under $project_root/ci/
#   CI_HOME       - (optional) override workspace root
#   artifacts_dir - path to the artefacts directory; mounted into the container
#
# Exports:
#   test_workspace  - path to the temporary working directory for this run
#   test_container  - name of the Docker container for this run
#
# Provider interface (all exported):
#   provider_run     - create and start the container, retrying up to 10 times
#   provider_exec    - run a bash --login command inside the container;
#                      writes stderr to $OUTPUT (default /dev/null)
#   provider_stop    - stop the container with a configurable timeout (default 60s)
#   provider_remove  - force-stop (1s timeout) and remove the container
#   provider_cleanup - remove container if it exists, then delete test_workspace
#
# Notes:
#   - If the container already exists from a previous interrupted run it is
#     reused rather than recreated, and the matching workspace directory is
#     located by glob rather than created fresh.
#   - Set OUTPUT to a file path before calling provider_exec to capture stderr
#     for post-mortem inspection.
################################################################################

_container_exists() {
  docker inspect "${1:?"Missing argument container_name"}" &>/dev/null
}

_container_state() {
  docker inspect --format '{{.State.Status}}' "${1:?"Missing argument container_name"}" 2>/dev/null
}

provider_run() {
  local max_attempts=10
  readonly max_attempts
  local attempt=1

  echo ""
  echo "Starting container '${test_container}'..."
  echo ""

  while true; do
    if ! _container_exists "${test_container}"; then
      docker create \
        --name "${test_container}" \
        --volume "${test_workspace}:${test_workspace}" \
        --volume "${artifacts_dir}:${artifacts_dir}" \
        "${base_container}"
    fi

    if [[ "$(_container_state "${test_container}")" != "running" ]]; then
      docker start "${test_container}"
    fi

    echo "Waiting for container to be ready..."
    if docker exec "${test_container}" true &>/dev/null; then
      break
    fi

    if [[ "${attempt}" -ge "${max_attempts}" ]]; then
      echo "Container not ready, max attempts exceeded (${attempt}), script exiting..."
      exit 1
    else
      echo "Container not ready, retrying (${attempt})..."
      provider_stop
    fi
    attempt=$((attempt + 1))
  done
}
export -f provider_run

provider_exec() {
  local output="${OUTPUT:-"/dev/null"}"
  readonly output

  if ! docker exec "${test_container}" /usr/bin/env bash --login -c "${@}" 2>"${output}"; then
    if [[ "${output}" != "/dev/null" && -f "${output}" ]]; then
      echo "Script failed"
      cat "${output}"
      exit 1
    fi
  fi
}
export -f provider_exec

provider_stop() {
  local timeout="${1:-60}"
  readonly timeout

  if [[ "$(_container_state "${test_container}")" != "exited" ]]; then
    if ! docker stop -t "${timeout}" "${test_container}"; then
      echo "could not stop container '${test_container}'"
      return 1
    fi
  fi
}
export -f provider_stop

provider_remove() {
  # timeout is set to 1 to force the environment to be destroyed right away
  provider_stop 1 || :
  docker rm "${test_container}"
}
export -f provider_remove

provider_cleanup() {
  set +u
  if [[ -n "${test_container}" ]]; then
    if _container_exists "${test_container}"; then
      provider_stop 1 || :
      docker rm "${test_container}"
    fi
  fi
  rm -rf "${test_workspace}"
}
export -f provider_cleanup

readonly base_container="${repo_name}.base"
if ! _container_exists "${base_container}"; then
  echo "Could not find base image used for testing..." >&2
  echo "Please run 'build_base_image.sh' and try again." >&2
  exit 1
fi

export test_container="${repo_name}.${git_sha}"
readonly test_container

if ! _container_exists "${test_container}"; then
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
