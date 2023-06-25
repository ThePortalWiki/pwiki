#!/bin/bash

set -euo pipefail

if [[ "$#" != 1 ]]; then
	echo "Usage:  $0 path/to/backup-YYYY-MM-DD.tar.xz" >&2
	exit 1
fi

backupFile="$1"
source /etc/pwiki/pwiki-secrets/secrets.sh

do_mysql() {
	docker exec -i pwiki-mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD"
}

echo 'Restoring database backup...' >&2
# Try to connect for a bit, database may not have fully started up yet.
for i in $(seq 1 10); do
	if ! echo 'SELECT 1;' | do_mysql &>/dev/null; then
		sleep 10
	fi
done
(echo "DROP DATABASE '$MYSQL_DATABASE';" | do_mysql) || true 2>/dev/null
(echo "DROP USER '$MYSQL_USER';" | do_mysql) || true 2>/dev/null
(echo "DROP USER '$READONLY_USER';" | do_mysql) || true 2>/dev/null
tar -axf "$backupFile" --wildcards '*.sql.xz' -O | xz -d | do_mysql
echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';" | do_mysql
echo "CREATE USER '$READONLY_USER'@'%' IDENTIFIED BY '$READONLY_PASSWORD';" | do_mysql
echo "GRANT ALL PRIVILEGES ON $MYSQL_DATABASE.* TO '$MYSQL_USER'@'%';" | do_mysql
echo "GRANT SELECT ON $MYSQL_DATABASE.* TO '$READONLY_USER'@'%';" | do_mysql
echo 'FLUSH PRIVILEGES;' | do_mysql

echo 'Restoring images...' >&2
tar -xf "$backupFile" -C /home/pwiki/www-private/ 'images'

rm "$backupFile"
echo 'Backup restored and removed from filesystem.' >&2
