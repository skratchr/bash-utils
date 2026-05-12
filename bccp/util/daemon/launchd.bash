################################################################################
# daemon/launchd.bash
#
# Service lifecycle helpers for macOS launchd system daemons.
#
# Intended for test harnesses that need to install, start, and cleanly tear
# down a Launch Daemon as part of a test run.
#
# Usage:
#   source daemon/launchd.bash
#
# Environment (consumed on source):
#   BUNDLE_ID_PREFIX - top-level bundle ID prefix, e.g. "com.acme.app"
#   BUNDLE_TARGET    - service name appended to the prefix, e.g. "daemon"
#                      together these produce app_id = "com.acme.app.daemon"
#
# Exports:
#   bundle_id_prefix  - resolved value of BUNDLE_ID_PREFIX
#   app_id            - full "${bundle_id_prefix}.${BUNDLE_TARGET}" identifier
#   launchd_path      - "/Library/LaunchDaemons/${app_id}.plist"
#   defaults_domain   - "/Library/Preferences/${app_id}.plist"
#                       consumed by config/plist.bash
#
# Functions:
#   service_running   - returns 0 if the service is currently active
#   service_load      - bootstraps the service; no-op if already running
#   service_unload    - boots out the service and waits for teardown;
#                       falls back to launchctl unload if bootout fails;
#                       timeout defaults to 30s (pass as second argument to override)
#
# Notes:
#   - All launchctl and defaults calls use sudo; the caller must have
#     passwordless sudo or run in an environment where it is pre-authorised.
#   - service_unload only acts if the plist file exists at launchd_path.
#   - log_stderr is expected to be defined by the sourcing harness.
################################################################################

# This should be the top level prefix of your app. Usually this will be
# com.company-name.app
readonly bundle_id_prefix="${BUNDLE_ID_PREFIX:?"Missing environment variable BUNDLE_ID_PREFIX"}"
export bundle_id_prefix

# This should be name of launch daemon excluding the top level prefix.
readonly app_id="${bundle_id_prefix}.${BUNDLE_TARGET:?"Missing environment variable BUNDLE_TARGET"}"
export app_id

# This is the default convention for non-sandboxed system daemons
readonly launchd_path="/Library/LaunchDaemons/${app_id}.plist"
export launchd_path

# This is the default convention for configurations that are handled by defaults
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
