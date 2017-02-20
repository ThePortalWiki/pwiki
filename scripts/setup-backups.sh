#!/usr/bin/env bash

set -euxo pipefail

if [ "$(whoami)" != root ]; then
	echo 'Run me as root.' >&2
	exit 1
fi
if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <pwiki secrets directory>" >&2
	exit 1
fi
secretsDir="$1"
if [ ! -f "$secretsDir/dbinfo.sh" ]; then
	echo "Secrets not found in '$secretsDir'." >&2
	exit 1
fi

repoDir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backupResourcesDir="$repoDir/resources/backups"

BACKUP_USER=pwikibackup
WEB_USER=pwiki
IMAGES_DIR="$(eval echo "~$WEB_USER/www/w/images")"
SSHD_CONFIG=/etc/ssh/sshd_config

if ! getent passwd "$BACKUP_USER" &> /dev/null; then
	useradd -U "$BACKUP_USER"
fi
if [ ! -f "$IMAGES_DIR/README" ]; then
	echo "Images directory '$IMAGES_DIR' does not exist or does not contain expected README file." >&2
	exit 1
fi
usermod -aG "$(stat -c '%G' "$IMAGES_DIR")" "$BACKUP_USER"
if ! su -c "ls '$IMAGES_DIR'" "$BACKUP_USER" &> /dev/null; then
	echo "Backup user '$BACKUP_USER' cannot read images directory '$IMAGES_DIR' despite the best efforts of this script. Please fix." >&2
	exit 1
fi
if [ ! -f "$SSHD_CONFIG" ]; then
	echo "sshd config '$SSHD_CONFIG' does not exist." >&2
	exit 1
fi

BACKUP_HOME="$(eval echo "~$BACKUP_USER")"
DATABASE_BACKUP_DIRECTORY="$BACKUP_HOME/database-backups"

umask 077
mkdir -p -m 700 "$DATABASE_BACKUP_DIRECTORY"
cp -f "$backupResourcesDir/backup.sh" "$BACKUP_HOME/backup.sh"
mkdir -p -m 700 "$BACKUP_HOME/.ssh"
cat "$backupResourcesDir/authorized_keys"/* > "$BACKUP_HOME/.ssh/authorized_keys"
chmod 400 "$BACKUP_HOME/.ssh/authorized_keys"
chmod 550 "$BACKUP_HOME/backup.sh"
ln -fs backup.sh "$BACKUP_HOME/backup"
chmod 500 "$BACKUP_HOME"
chown -R "$BACKUP_USER:$BACKUP_USER" "$BACKUP_HOME"
cat << EOF > /etc/cron.weekly/pwiki-database-backup.sh
#!/usr/bin/env bash

exec cronic bash -c '"$repoDir/scripts/backup-database.sh" "$secretsDir" "$DATABASE_BACKUP_DIRECTORY/pwiki-\$(date '+%Y-%m-%d').sql.xz"'
EOF
cat << EOF > /etc/cron.weekly/pwiki-database-backup-cleanup.sh
#!/usr/bin/env bash

exec cronic find '$DATABASE_BACKUP_DIRECTORY' -type f -mtime +30 -delete
EOF
chmod 555 /etc/cron.weekly/pwiki-database-backup.sh /etc/cron.weekly/pwiki-database-backup-cleanup.sh

tmpSSHDConfig="$SSHD_CONFIG.pwiki-tmp"
cat "$SSHD_CONFIG" | sed -r 's/.*#.*MANAGED_BY_PWIKI.*$//g' > "$tmpSSHDConfig"
cat << EOF >> "$tmpSSHDConfig"

# The following section is managed by PWiki. Do not edit. # MANAGED_BY_PWIKI
Match user                          $BACKUP_USER          # MANAGED_BY_PWIKI
    PasswordAuthentication          no                    # MANAGED_BY_PWIKI
    AllowTCPForwarding              no                    # MANAGED_BY_PWIKI
    PermitTTY                       no                    # MANAGED_BY_PWIKI
    PermitTunnel                    no                    # MANAGED_BY_PWIKI
    X11Forwarding                   no                    # MANAGED_BY_PWIKI
    ForceCommand                    $BACKUP_HOME/backup   # MANAGED_BY_PWIKI
# End of section managed by PWiki.                        # MANAGED_BY_PWIKI
EOF
chmod --reference="$SSHD_CONFIG" "$tmpSSHDConfig"
chown --reference="$SSHD_CONFIG" "$tmpSSHDConfig"
mv "$tmpSSHDConfig" "$SSHD_CONFIG"
