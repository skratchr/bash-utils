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
	# maps property name to property list type
	declare -rA config_properties=(
		["some_string"]="string"
		["some_bool"]="bool"
		["some_int"]="integer"
		["some_array"]="array"
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
