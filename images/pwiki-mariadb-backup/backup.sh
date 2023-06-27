#!/usr/bin/env bash

set -euo pipefail

if [ -e /pwiki-secrets/no-volume -o -e /backups/no-volume ]; then
	echo 'Volumes not mounted.' >&2
	exit 1
fi
source /pwiki-secrets/dbinfo.sh
if [ -z "$READONLY_USER" -o -z "$READONLY_PASSWORD" ]; then
	echo '/pwiki-secrets/dbinfo.sh does not contain the expected environment variables.' >&2
	exit 1
fi

if [ "$#" -ne 1 ]; then
	echo "Must provide exactly one argument (backup file) as argument. Got $#: '$@'" >&2
	exit 1
fi
BACKUP_FILE="$1"
if echo "$BACKUP_FILE" | grep -q /; then
	echo "Backup file '$BACKUP_FILE' must not contain slashes." >&2
	exit 1
fi
if ! echo "$BACKUP_FILE" | grep -qP '\.sql.xz$'; then
	echo "Backup file '$BACKUP_FILE' must end with extension '.sql.xz'." >&2
	exit 1
fi

umask 077
tempConfig="$(mktemp --suffix='.my.cnf')"
cat << EOF > "$tempConfig"
[mysqldump]
user=$READONLY_USER
password=$READONLY_PASSWORD
EOF
tempDump="/backups/.$BACKUP_FILE.partial.$RANDOM.tmp"
mariadb-dump --defaults-file="$tempConfig"          \
    --single-transaction --quick --extended-insert  \
    --max_allowed_packet=64M -h pwiki-mariadb       \
    --all-databases --all-tablespaces > "$tempDump"
rm -f "$tempConfig"
xz --lzma2 -e9 --memlimit-compress='50%' -T 1 "$tempDump"
rm -f "$tempDump"
chmod 440 "$tempDump.xz"
chown wikibackup:wikibackup "$tempDump.xz"
mv "$tempDump.xz" "/backups/$BACKUP_FILE"
