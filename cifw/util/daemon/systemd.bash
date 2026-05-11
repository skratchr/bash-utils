# This should be the name of the systemd service unit, without the .service suffix.
readonly service_name="${SERVICE_NAME?:"Missing environment variable SERVICE_NAME"}"
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
