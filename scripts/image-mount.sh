#!/usr/bin/env bash

set -euxo pipefail

WEB_USER=pwiki
WEB_GROUP=pwiki
WEB_HOME="$(eval echo "~$WEB_USER")"
WEBROOT="$WEB_HOME/www"
IMAGES_ROOT="$WEB_HOME/www-private/images"

if [ ! -d "$WEBROOT" ]; then
	echo "Cannot find MediaWiki root '$WEBROOT'." >&2
	exit 1
fi

if [ ! -d "$IMAGES_ROOT" ]; then
	echo "Cannot find images root '$IMAGES_ROOT'." >&2
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
		chown "$WEB_USER:$WEB_GROUP" "$MOUNTPOINT"
	fi
	if [ "$(ls -1 "$MOUNTPOINT" | wc -l)" -ne 0 ]; then
		echo "Mountpoint '$MOUNTPOINT' is not empty." >&2
		exit 1
	fi
	chown -R "$WEB_USER:$WEB_GROUP" "$IMAGES_ROOT"
	chmod -R o+rwX,g+rwX,o-w "$IMAGES_ROOT"
	mount --bind --make-rprivate -o allow_other,umask=0002 "$IMAGES_ROOT" "$MOUNTPOINT"
	exit 0
fi

if [ "$1" == unmount ]; then
	if [ "$(ls -1 "$MOUNTPOINT" | wc -l)" -eq 0 ]; then
		echo "Mountpoint '$MOUNTPOINT' is empty." >&2
		exit 1
	fi
	umount -l -R "$MOUNTPOINT"
	rmdir "$MOUNTPOINT"
	exit 0
fi

echo 'First argument must be "mount" or "unmount".' >&2
exit 1
