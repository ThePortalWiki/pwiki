#!/bin/bash

set -euo pipefail

DATABASE_BACKUPS_DIR="$HOME/database-backups"
MAX_BACKUP_AGE_SECONDS="$((15 * 24 * 60 * 60))"  # 15 days, a bit over 2 weeks.
WEB_USER='pwiki'
BACKUP_GNUPG_SIGNING_KEY='pwikibackup@theportalwiki.com'
BACKUP_GNUPG_SIGNING_PRIVATE_KEY_FILE="$HOME/signing-key.asc"
BACKUP_GNUPG_ENCRYPTION_KEY='staff@theportalwiki.com'
BACKUP_GNUPG_ENCRYPTION_PUBLIC_KEY_FILE="$HOME/encryption-key.pub.asc"
SECRETS_FILE='/etc/pwiki/pwiki-secrets/secrets.sh'
REPO_DIR='/home/pwiki/pwiki'
IMAGES_DIR="$(eval echo "~$WEB_USER/www/w/images")"

howOld() {
	totalSecondsOld="$1"
	if [ "$totalSecondsOld" -eq 0 ]; then
		echo '<1s'
		return 0
	fi
	secondsOld="$(expr "$totalSecondsOld" '%' 60)"
	totalMinutesOld="$(expr "$totalSecondsOld" '/' 60)"
	minutesOld="$(expr "$totalMinutesOld" '%' 60)"
	totalHoursOld="$(expr "$totalMinutesOld" '/' 60)"
	hoursOld="$(expr "$totalHoursOld" '%' 24)"
	totalDaysOld="$(expr "$totalHoursOld" '/' 24)"

	duration=''
	if [ "$secondsOld" -gt 0 ]; then
		duration="${secondsOld}s $duration"
	fi
	if [ "$minutesOld" -gt 0 ]; then
		duration="${minutesOld}m $duration"
	fi
	if [ "$hoursOld" -gt 0 ]; then
		duration="${hoursOld}h $duration"
	fi
	if [ "$totalDaysOld" -gt 0 ]; then
		duration="${totalDaysOld}d $duration"
	fi
	echo "$duration" | sed -r 's/^ *| *$//g'
}

latestDatabaseBackup="$(ls -1t "$DATABASE_BACKUPS_DIR"/*.sql.xz | head -1)"
if [ "$(echo "$latestDatabaseBackup" | wc -l)" -eq 0 ]; then
	echo "Cannot find any database backup in database backup directory '$DATABASE_BACKUPS_DIR'." >&2
	exit 1
fi
backupTimestamp="$(stat -c '%W' "$latestDatabaseBackup")"
if [ "$backupTimestamp" -eq 0 ]; then
	backupTimestamp="$(stat -c '%Y' "$latestDatabaseBackup")"
fi
currentTimestamp="$(date '+%s')"
if [ "$currentTimestamp" -lt "$backupTimestamp" ]; then
	echo "Database backup '$latestDatabaseBackup' was created in the future somehow." >&2
	exit 1
fi
backupAgeSeconds="$(expr "$currentTimestamp" - "$backupTimestamp")"
if [ "$backupAgeSeconds" -gt "$MAX_BACKUP_AGE_SECONDS" ]; then
	echo "Latest database backup '$latestDatabaseBackup' was created $(howOld "$backupAgeSeconds") ago, which is older than the maximum allowed backup age of $(howOld "$MAX_BACKUP_AGE_SECONDS")." >&2
	exit 1
fi
if ! ls "$IMAGES_DIR" &> /dev/null; then
	echo "Cannot read images directory '$IMAGES_DIR'." >&2
	exit 1
fi
echo "Selected database backup file: '$latestDatabaseBackup' ($(howOld "$backupAgeSeconds") old)." >&2
tmpDir="$(mktemp -d)"
export GNUPGHOME="$tmpDir/.gnupg"
mkdir -m700 "$GNUPGHOME"
gpg --batch --quiet --import < "$BACKUP_GNUPG_SIGNING_PRIVATE_KEY_FILE" 2>/dev/null || echo 'GnuPG error while importing signing key.' >&2
gpg --batch --quiet --import < "$BACKUP_GNUPG_ENCRYPTION_PUBLIC_KEY_FILE" 2>/dev/null || echo 'GnuPG error while importing encryption public key.' >&2

echo 'Streaming backup file...' >&2
tar --create --file=- --xz --one-file-system                                             \
  --warning=no-file-changed --exclude='*/thumb/*' --exclude='*/temp/*'                   \
  --directory="$(dirname "$SECRETS_FILE")" "$(basename "$SECRETS_FILE")" \
  --directory="$(dirname "$latestDatabaseBackup")" "$(basename "$latestDatabaseBackup")" \
  --directory="$(dirname "$REPO_DIR")" "$(basename "$REPO_DIR")" \
  --directory="$(dirname "$IMAGES_DIR")"           "$(basename "$IMAGES_DIR")" |         \
gpg --batch --quiet                                                                      \
  --sign --local-user="$BACKUP_GNUPG_SIGNING_KEY"                                        \
  --encrypt --recipient="$BACKUP_GNUPG_ENCRYPTION_KEY" --trust-model=always |            \
gpg --batch --quiet                                                                      \
  --sign --local-user="$BACKUP_GNUPG_SIGNING_KEY"

echo 'Backup file streamed successfully.' >&2

rm -rf --one-file-system "$tmpDir"
