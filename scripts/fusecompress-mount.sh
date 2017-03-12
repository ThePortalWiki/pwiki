#!/usr/bin/env bash

set -euxo pipefail

WEBROOT="$HOME/www"
IMAGES_ROOT="$HOME/www-private/pwiki-images"
FUSECOMPRESS="$HOME/fusecompress/install/bin/fusecompress"

if [ ! -d "$WEBROOT" ]; then
	echo "Cannot find MediaWiki root '$WEBROOT'." >&2
	exit 1
fi

if [ ! -d "$IMAGES_ROOT" ]; then
	echo "Cannot find images root '$IMAGES_ROOT'." >&2
	exit 1
fi

if [ ! -x "$FUSECOMPRESS" ]; then
	echo "Cannot find fusecompress binary '$FUSECOMPRESS'." >&2
	exit 1
fi

if [ "$#" != 1 ]; then
	echo "Usage: $0 <mount|unmount>" >&2
	exit 1
fi

MOUNTPOINT="$WEBROOT/w/images"

if [ "$1" == mount ]; then
	if [ ! -d "$MOUNTPOINT" ]; then
		mkdir --mode=700 "$MOUNTPOINT"
	fi
	if [ "$(ls -1 "$MOUNTPOINT" | wc -l)" -ne 0 ]; then
		echo "Mountpoint '$MOUNTPOINT' is not empty." >&2
		exit 1
	fi
	"$FUSECOMPRESS" -o allow_other,umask=0002 -c lzma -l 9 "$IMAGES_ROOT" "$MOUNTPOINT"
	exit 0
fi

if [ "$1" == unmount ]; then
	if [ "$(ls -1 "$MOUNTPOINT" | wc -l)" -eq 0 ]; then
		echo "Mountpoint '$MOUNTPOINT' is empty." >&2
		exit 1
	fi
	fusermount -u "$MOUNTPOINT"
	rmdir "$MOUNTPOINT"
	exit 0
fi

echo 'First argument must be "mount" or "unmount".' >&2
exit 1
