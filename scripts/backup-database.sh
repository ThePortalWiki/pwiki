#!/usr/bin/env bash

set -euxo pipefail

repoDir="$(dirname "${BASH_SOURCE[0]}")/.."
imagesDir="$repoDir/images"
backupContainerName='pwiki-mariadb-backup'

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <secrets directory> <backup file path>" >&2
	exit 1
fi

SECRETS_DIR="$1"
if [ ! -e "$SECRETS_DIR/dbinfo.sh" ]; then
	echo "Secrets directory '$SECRETS_DIR' does not contain the expected dbinfo.sh." >&2
	exit 1
fi
BACKUP_FILE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
if [ -f "$BACKUP_FILE" ]; then
	echo "Warning: Backup file '$2' already exists. It will be overwritten."
	echo 'You have 30 seconds to cancel this script before it risks being overwritten.'
	sleep 30
fi
if [ ! -d "$(dirname "$BACKUP_FILE")" ]; then
	echo "Backup file '$BACKUP_FILE' is in non-existent directory '$(dirname "$BACKUP_FILE")'." >&2
	exit 1
fi
BACKUP_UIDGID="$(stat -c '%u:%g' "$(dirname "$BACKUP_FILE")")"

docker build --quiet                              \
    --build-arg="BACKUP_UIDGID=$BACKUP_UIDGID"    \
    --tag="$backupContainerName"                  \
    "$imagesDir/$backupContainerName" > /dev/null

docker rm -f "$backupContainerName" &>/dev/null || true

docker run --rm --name="$backupContainerName"     \
    --volume="$SECRETS_DIR:/pwiki-secrets"        \
    --volume="$(dirname "$BACKUP_FILE"):/backups" \
    --link=pwiki-mariadb                          \
    "$backupContainerName" "$(basename "$BACKUP_FILE")"

if [ ! -f "$BACKUP_FILE" ]; then
	echo "Sanity check failed: '$BACKUP_FILE' does not exist despite docker run success." >&2
	exit 1
fi
echo "Successfully backed up database to '$BACKUP_FILE'." >&2
