#!/usr/bin/env bash
################################################################################
# network/configd.bash
#
# macOS underlay network inspection and manipulation helpers.
#
# Intended for test groups that need to inspect or manipulate the host network
# configuration — for example, to test behaviour when service order changes or
# when a specific interface is primary.
#
# Usage:
#   source network/configd.bash
#
# This file should be sourced at the top level of a test suite so that the
# captured UUIDs remain immutable for the duration of the run. If an IPsec
# tunnel is detected, or no primary service is found, the file returns early
# without exporting anything.
#
# Exports:
#   primary_service_uuid   - UUID of the active primary network service
#   secondary_service_uuid - UUID of a secondary routable service, if one exists
#
# Functions (all exported):
#   scq uuid                   - run scutil "show <key>" and print the result
#   device uuid                - interface name for a service UUID
#   gw uuid                    - default gateway for a service UUID
#   dns uuid                   - semicolon-separated DNS servers for a service UUID
#   switch_service_order a b   - swap the network service order of UUIDs a and b
#
# Notes:
#   - All functions read live state from SCDynamicStore via scutil; they reflect
#     the current system state at call time, not a snapshot.
#   - switch_service_order calls networksetup with sudo; the caller must have
#     appropriate privileges.
#   - The file skips execution silently if an IPsec interface is present, since
#     reordering services in that state is not meaningful.
################################################################################

scq() { echo "show ${1}" | /usr/sbin/scutil; }

# Switches the order between two network services based on their UUID
switch_service_order() {
	local new_a a
	read -r a < <(
		scq "Setup:/Network/Service/${1:?"Missing argument first uuid"}" |
			grep "UserDefinedName :" |
			sed 's/.*UserDefinedName : //'
	)

	local new_b b
	read -r b < <(
		scq "Setup:/Network/Service/${2:?"Missing argument second uuid"}" |
			grep "UserDefinedName :" |
			sed 's/.*UserDefinedName : //'
	)

	if [[ -z "${a}" || -z "${b}" ]]; then return; fi

	local service_order
	mapfile -t service_order < <(
		/usr/sbin/networksetup -listnetworkserviceorder |
			grep -E "^\([0-9]\)" |
			sed 's/^([0-9]*) //'
	)

	for ((i = 0; i < ${#service_order[@]}; i++)); do
		case "${service_order[i]}" in
		"${a}") new_b=$i ;;
		"${b}") new_a=$i ;;
		esac
		if [[ -n "${new_a}" && -n "${new_b}" ]]; then break; fi
	done

	if [[ -z "${new_a}" || -z "${new_b}" ]]; then
		echo "Service not found in order list" >&2
		return 1
	fi

	local before="${service_order[*]}"
	service_order[new_b]="${b}"
	service_order[new_a]="${a}"
	local after="${service_order[*]}"
	echo "* Changed service order"
	echo "from:  ${before}"
	echo "to:    ${after}"
	sudo /usr/sbin/networksetup -ordernetworkservices "${service_order[@]}"
	unset service_order before after a b new_a new_b
}

device() {
	scq "State:/Network/Service/${1:?"Missing argument uuid"}/IPv4" |
		grep "ConfirmedInterfaceName :" |
		awk '{ print $3 }'
}

gw() {
	scq "State:/Network/Service/${1:?"Missing argument uuid"}/IPv4" |
		grep "Router :" |
		awk '{ print $3 }'
}

dns() {
	mapfile -t v < <(
		scq "State:/Network/Service/${1:?"Missing argument uuid"}/DNS" |
			sed -n '/ServerAddresses/,/}/p' |
			grep -E '^[[:space:]]+[0-9]' |
			awk '{print $3}'
	)
	(
		IFS=";"
		echo "${v[*]}"
	)
}

# No point snapshotting an environment where an IPsec tunnel exists
if ifconfig | grep -q ipsec 2>/dev/null; then return; fi

read -r uuid < <(scq "State:/Network/Global/IPv4" | grep "PrimaryService" | awk '{ print $3 }')
if [[ -z "${uuid}" ]]; then return; fi

export -f switch_service_order
export -f device
export -f dns
export -f gw

echo "Saving primary service UUID..."
declare -grx primary_service_uuid="${uuid}"
unset uuid

for uuid in $(scq "Setup:/Network/Global/IPv4" | grep -oEi "[A-F0-9]{8}-([A-F0-9]{4}-){3}[A-F0-9]{12}"); do
	if [[ "${uuid}" != "${primary_service_uuid}" ]] &&
		/sbin/route -n get -ifscope "$(device "${uuid}")" google.com 2>/dev/null 1>&2; then
		echo "Saving secondary service UUID..."
		declare -grx secondary_service_uuid="${uuid}"
		break
	fi
done
unset uuid
