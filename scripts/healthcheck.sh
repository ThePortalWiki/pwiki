#!/bin/bash

set -euo pipefail

mode="$1"
if [[ "$mode" != '--local' ]] && [[ "$mode" != '--remote' ]]; then
	echo 'Invalid usage.' >&2
	exit 1
fi
shift
if [[ "$mode" == '--remote' ]]; then
	pwikiDomain="$1"
	shift
fi

checkLocalMainPage() {
	curl --connect-timeout 15 --max-time 20 --retry-max-time 30 --insecure "https://127.0.0.1/wiki/Main_Page"
}

checkDomainMainPage() {
	curl --connect-timeout 15 --max-time 20 --retry-max-time 30 "https://$pwikiDomain/wiki/Main_Page"
}

if [[ "$mode" == '--local' ]]; then
	localSuccess=false
	for i in $(seq 1 10); do
		if checkLocalMainPage &>/dev/null; then
			localSuccess=true
			break
		fi
		sleep 30
	done
	if [[ "$localSuccess" == false ]]; then
		echo 'Local health check failed, rebooting in 10 seconds.' >&2
		sleep 10
		reboot
		exit 1
	fi
else
	remoteSuccess=false
	for i in $(seq 1 10); do
		if checkDomainMainPage &>/dev/null; then
			remoteSuccess=true
			break
		fi
		sleep 180
	done
	if [[ "$remoteSuccess" == false ]]; then
		echo 'Remote health check failed, rebooting in 10 seconds.' >&2
		sleep 10
		reboot
		exit 1
	fi
fi
