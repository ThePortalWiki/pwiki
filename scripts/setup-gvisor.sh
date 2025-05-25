#!/bin/bash

set -euo pipefail

BASE_URL="https://storage.googleapis.com/gvisor/releases/release/latest/$(uname -m)"
INSTALL_PATH=/usr/bin
BINARIES=(
	runsc
	containerd-shim-runsc-v1
)
redownloaded=false
for binary in "${BINARIES[@]}"; do
	BINARY_PATH="/usr/bin/$binary"
	need_redownload=false
	if [[ ! -f "$BINARY_PATH" ]]; then
		need_redownload=true
	else
		latest_sha512="$(curl -fSsl "$BASE_URL/$binary.sha512" | cut -d' ' -f1)"
		if [[ -z "$latest_sha512" ]]; then
			echo 'Cannot get latest release hash.' >&2
			exit 1
		fi
		if [[ "$(sha512sum "$BINARY_PATH" | cut -d' ' -f1)" != "$latest_sha512" ]]; then
			need_redownload=true
		fi
	fi

	if [[ "$need_redownload" == false ]]; then
		continue
	fi

	while true; do
		rm -f "$BINARY_PATH.tmp" &>/dev/null || true
		if ! curl -fSsl "$BASE_URL/$binary" > "$BINARY_PATH.tmp"; then
			echo 'Cannot get latest release.' >&2
			exit 1
		fi
		latest_sha512="$(curl -fSsl "$BASE_URL/$binary.sha512" | cut -d' ' -f1)"
		if [[ -z "$latest_sha512" ]]; then
			echo 'Cannot get latest release hash.' >&2
			exit 1
		fi
		chown root:root "$BINARY_PATH.tmp"
		chmod 755 "$BINARY_PATH.tmp"
		if [[ "$(sha512sum "$BINARY_PATH.tmp" | cut -d' ' -f1)" != "$latest_sha512" ]]; then
			echo 'Hash mismatch, retrying...' >&2
			rm -f "$BINARY_PATH.tmp" &>/dev/null || true
			continue
		fi
		mv "$BINARY_PATH.tmp" "$BINARY_PATH"
		break
	done
	redownloaded=true
done

if [[ "$redownloaded" == false ]]; then
	exit 0
fi
/usr/bin/runsc install -- --host-uds=all --platform=systrap --systrap-disable-syscall-patching=true
systemctl restart docker
