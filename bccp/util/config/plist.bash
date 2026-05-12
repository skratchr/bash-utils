################################################################################
# config/plist.bash
#
# macOS plist read/write helpers for daemon configuration.
#
# Provides a type-aware plist generator and a defaults-based read/write
# interface for configuring and validating a Launch Daemon's preference domain.
#
# Usage:
#   source daemon/launchd.bash   # sets defaults_domain
#   source config/plist.bash
#
# Prerequisites:
#   defaults_domain must be set before calling any function in this file.
#   daemon/launchd.bash exports it as "/Library/Preferences/${app_id}.plist".
#
# Caller responsibilities:
#   generate_plist contains a config_properties map that must be populated for
#   your specific daemon before this file is sourced. The map associates each
#   property name (lowercased) with its plist type. Supported types:
#
#     bool        - rendered as <true/> or <false/>; accepts 0/1/true/false
#     array       - rendered as <array> of <string> elements; value is a
#                   comma-separated list, e.g. "a,b,c"
#     dictionary  - skipped (not currently rendered)
#     <any other> - rendered as <${type}>${value}</${type}>, e.g. "string",
#                   "integer", "real"
#
#   Replace the placeholder entry in config_properties with your actual
#   property-to-type mappings before sourcing.
#
# Functions:
#   generate_plist [key value ...]
#       Emit a complete plist XML document to stdout. Arguments are pairs of
#       property name and value; the type is looked up from config_properties.
#
#   write_config [key value ...]
#       Delete the current preference domain, regenerate it from the given
#       key/value pairs, convert to binary1, and import via defaults.
#       Logs the resulting configuration to stderr.
#
#   validate_plist [key value ...]
#       Read each key from the defaults domain and compare against the expected
#       value. Logs mismatches via log_stderr and returns 1 if any are found.
#
# Notes:
#   - All defaults and plutil calls use sudo; the caller must have appropriate
#     privileges.
#   - log_stderr is expected to be defined by the sourcing harness.
################################################################################

validate_plist() {
	local conf=("${@}")
	local k ev av
	local result=0

	for ((i = 0; i < "${#conf[@]}"; i += 2)); do
		k="${conf[i]}"
		ev="${conf[i+1]}"
		av="$(sudo defaults read "${defaults_domain}" "${k}")"

		if [[ "${ev}" != "${av}" ]]; then
			log_stderr "expected ${ev} for ${k}, got ${av}"
			result=1
		fi
		unset k ev av
	done
	return $result
}

write_config() {
	sudo defaults delete "${defaults_domain}" || :
	generate_plist "${@}" |
		sudo tee "${defaults_domain}" |
		plutil -convert binary1 -o - - |
		sudo defaults import "${defaults_domain}" -

	log_stderr "Configuration updated:"
	sudo defaults read "${defaults_domain}"
}

generate_plist() {
	local conf=("${@}")
	# Maps property name (lowercased) to plist type.
	# Callers must replace this with their actual property-to-type mappings.
	# Example:
	#   declare -rA config_properties=(
	#     ["serveraddress"]="string"
	#     ["port"]="integer"
	#     ["enablefeature"]="bool"
	#     ["alloweddomains"]="array"
	#   )
	declare -rA config_properties=(
		["<property_name>"]="<property_type>"
	)
	# output daemon compliant plist file
	cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$(
		for ((i = 0; i < ${#conf[@]}; i += 2)); do
			t="${config_properties[${conf[i],,}]}"
			v="${conf[i+1]}"
			echo -e "\t<key>${conf[i]}</key>"
			case "${t}" in
			bool)
				case "${v}" in
				0 | false)
					echo -e "\t<false/>"
					;;
				1 | true)
					echo -e "\t<true/>"
					;;
				*)
					echo "Attempted invalid value for boolean type"
					exit 1
					;;
				esac
				;;
			array)
				echo -e "\t<array>"
				IFS="," read -r -a values <<<"${v}"
				for value in "${values[@]}"; do
					echo -e "\t\t<string>${value}</string>"
				done
				echo -e "\t</array>"
				;;
			dictionary)
				continue
				;;
			*)
				echo -e "\t<${t}>${v}</${t}>"
				;;
			esac
		done
	)
</dict>
</plist>
EOF
}
