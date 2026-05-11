# This should be the top level prefix of your app. Usually this will be
# com.company-name.app
readonly bundle_id_prefix="${BUNDLE_ID_PREFIX?:"Missing environment variable BUNDLE_ID_PREFIX"}"
export bundle_id_prefix

# This should be name of launch daemon excluding the top level prefix.
readonly app_id="${bundle_id_prefix}.${BUNDLE_TARGET:?"Missing environment variable BUNDLE_TARGET"}"
export app_id

# This is the default convention for non-sandboxed system damons
readonly launchd_path="/Library/LaunchDaemons/${app_id}.plist"
export launchd_path

# This is the default convention for congfigurations that are handled by defaults
export defaults_domain="/Library/Preferences/${app_id}.plist"
readonly defaults_domain

service_running() {
	sudo launchctl print "system/${app_id}" &>/dev/null ||
		sudo launchctl list 2>/dev/null | grep -q "${app_id}"
}

service_load() {
	if service_running; then return; fi
	log_stderr "Bootstrap service (system ${launchd_path})"
	if ! sudo launchctl bootstrap system "${launchd_path}" 1>&2; then
		log_stderr "Could not bootstrap service (${launchd_path})"
		return 1
	fi
}

service_unload() {
	if ! service_running; then return; fi
	if [[ -f "${launchd_path}" ]]; then
		log_stderr "Bootout service (system/${app_id})"
		if ! sudo launchctl bootout system/"${app_id}" 1>&2; then
			log_stderr "Bootout failed, unload service ('${launchd_path})"
			if ! sudo launchctl unload "${launchd_path}" 2>/dev/null; then
				log_stderr "Could not unload service"
				return 1
			fi
		fi

		local timeout="${2:-30}"
		readonly timeout

		local expired=$((SECONDS + timeout))
		readonly expired
		while service_running; do
			if [[ "${SECONDS}" -ge "${expired}" ]]; then
				log_stderr "Timeout waiting for ${app_id} to finish teardown (${timeout})"
				return 1
			fi
			log_stderr "Waiting for ${app_id} to finish teardown..."
			sleep 3
		done
	fi
}
