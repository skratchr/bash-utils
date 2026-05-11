################################################################################
# daemon/systemd.bash
#
# Service lifecycle helpers for Linux systemd services.
#
# Mirrors the interface of daemon/launchd.bash so that a test harness can swap
# between the two by changing which file it sources.
#
# Usage:
#   source daemon/systemd.bash
#
# Environment (consumed on source):
#   SERVICE_NAME - systemd unit name, without the .service suffix
#                  e.g. "my-app" resolves to "my-app.service"
#
# Exports:
#   service_name - resolved value of SERVICE_NAME
#   service_unit - "${service_name}.service"
#
# Functions:
#   service_running   - returns 0 if the unit is currently active
#   service_load      - starts the unit; no-op if already running
#   service_unload    - stops the unit and waits for teardown;
#                       timeout defaults to 30s (pass as second argument to override)
#
# Notes:
#   - Unlike launchd.bash, no sudo is used; run as a user with the appropriate
#     systemctl privileges, or in a context where sudo is not required.
#   - log_stderr is expected to be defined by the sourcing harness.
################################################################################

# This should be the name of the systemd service unit, without the .service suffix.
readonly service_name="${SERVICE_NAME:?"Missing environment variable SERVICE_NAME"}"
export service_name

readonly service_unit="${service_name}.service"
export service_unit

service_running() {
	systemctl is-active --quiet "${service_unit}"
}

service_load() {
	if service_running; then return; fi
	log_stderr "Starting service (${service_unit})"
	if ! systemctl start "${service_unit}" 1>&2; then
		log_stderr "Could not start service (${service_unit})"
		return 1
	fi
}

service_unload() {
	if ! service_running; then return; fi

	log_stderr "Stopping service (${service_unit})"
	if ! systemctl stop "${service_unit}" 1>&2; then
		log_stderr "Could not stop service (${service_unit})"
		return 1
	fi

	local timeout="${2:-30}"
	readonly timeout

	local expired=$((SECONDS + timeout))
	readonly expired

	while service_running; do
		if [[ "${SECONDS}" -ge "${expired}" ]]; then
			log_stderr "Timeout waiting for ${service_name} to finish teardown (${timeout})"
			return 1
		fi
		log_stderr "Waiting for ${service_name} to finish teardown..."
		sleep 3
	done
}
