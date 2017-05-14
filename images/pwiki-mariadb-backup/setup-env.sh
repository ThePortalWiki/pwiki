#!/usr/bin/env bash

set -euo pipefail

BACKUP_UID="$(echo "$BACKUP_UIDGID" | cut -d: -f1)"
BACKUP_GID="$(echo "$BACKUP_UIDGID" | cut -d: -f2)"
if ! echo "$BACKUP_UID" | grep -qP '^[0-9]+$'; then
	echo "Invalid UID:GID pair: '$BACKUP_UIDGID'" >&2
	exit 1
fi
if ! echo "$BACKUP_GID" | grep -qP '^[0-9]+$'; then
	echo "Invalid UID:GID pair: '$BACKUP_UIDGID'" >&2
	exit 1
fi
groupadd --gid="$BACKUP_GID" wikibackup
useradd --uid="$BACKUP_UID" --gid=wikibackup -s /bin/true -d / -M wikibackup
