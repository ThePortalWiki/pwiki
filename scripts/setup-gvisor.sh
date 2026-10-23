#!/bin/bash

set -euo pipefail

BASE_URL="https://storage.googleapis.com/gvisor/releases/release/latest/$(uname -m)"
INSTALL_PATH=/usr/bin

compression=""
if command -v zstd >/dev/null 2>&1; then
	compression=zstd
	tar_flag='--zstd'
elif command -v bzip2 >/dev/null 2>&1; then
	compression=bz2
	tar_flag='-j'
else
	echo 'Neither zstd nor bzip2 is installed; cannot extract gVisor tarball.' >&2
	exit 1
fi
TARBALL_NAME="gvisor.tar.${compression}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
TARBALL_PATH="$WORKDIR/$TARBALL_NAME"
SHA_PATH="$WORKDIR/$TARBALL_NAME.sha512"

while true; do
	rm -f "$TARBALL_PATH" "$SHA_PATH"
	if ! curl -fSsl "$BASE_URL/$TARBALL_NAME" > "$TARBALL_PATH"; then
		echo 'Cannot get latest release.' >&2
		exit 1
	fi
	if ! curl -fSsl "$BASE_URL/$TARBALL_NAME.sha512" > "$SHA_PATH"; then
		echo 'Cannot get latest release hash.' >&2
		exit 1
	fi
	if ! ( cd "$WORKDIR" && sha512sum -c "$SHA_PATH" >/dev/null 2>&1 ); then
		echo 'Hash mismatch, retrying...' >&2
		continue
	fi
	break
done

EXTRACT_DIR="$WORKDIR/extract"
mkdir -p "$EXTRACT_DIR"
tar "$tar_flag" -xf "$TARBALL_PATH" -C "$EXTRACT_DIR"
chown -R root:root "$EXTRACT_DIR"
cp -a "$EXTRACT_DIR"/. "$INSTALL_PATH/"

/usr/bin/runsc install -- --host-uds=all --platform=systrap --systrap-disable-syscall-patching=true
systemctl restart docker
