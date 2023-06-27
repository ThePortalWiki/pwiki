#!/bin/bash

set -euo pipefail

RUNSC_PATH=/usr/bin/runsc
BASE_URL="https://storage.googleapis.com/gvisor/releases/release/latest/$(uname -m)"

need_redownload=false
if [[ ! -f "$RUNSC_PATH" ]]; then
	need_redownload=true
else
	latest_sha512="$(curl -fSsl "$BASE_URL/runsc.sha512" | cut -d' ' -f1)"
	if [[ -z "$latest_sha512" ]]; then
		echo 'Cannot get latest release hash.' >&2
		exit 1
	fi
	if [[ "$(sha512sum "$RUNSC_PATH" | cut -d' ' -f1)" != "$latest_sha512" ]]; then
		need_redownload=true
	fi
fi

if [[ "$need_redownload" == false ]]; then
	exit 0
fi

while true; do
	rm -f "$RUNSC_PATH.tmp" &>/dev/null || true
	if ! curl -fSsl "$BASE_URL/runsc" > "$RUNSC_PATH.tmp"; then
		echo 'Cannot get latest release.' >&2
		exit 1
	fi
	latest_sha512="$(curl -fSsl "$BASE_URL/runsc.sha512" | cut -d' ' -f1)"
	if [[ -z "$latest_sha512" ]]; then
		echo 'Cannot get latest release hash.' >&2
		exit 1
	fi
	chown root:root "$RUNSC_PATH.tmp"
	chmod 755 "$RUNSC_PATH.tmp"
	if [[ "$(sha512sum "$RUNSC_PATH.tmp" | cut -d' ' -f1)" != "$latest_sha512" ]]; then
		echo 'Hash mismatch, retrying...' >&2
		rm -f "$RUNSC_PATH.tmp" &>/dev/null || true
		continue
	fi
	mv "$RUNSC_PATH.tmp" "$RUNSC_PATH"
	break
done

"$RUNSC_PATH" install -- --host-uds=all
systemctl restart docker
