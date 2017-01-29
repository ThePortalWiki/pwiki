#!/usr/bin/env bash

set -e

if [ -e /pwiki-secrets/no-volume -o -e /var/lib/mysql/no-volume ]; then
	echo 'Volumes not mounted.' >&2
	exit 1
fi
source /pwiki-secrets/dbinfo.sh
if [ -z "$MYSQL_ROOT_PASSWORD" -o -z "$MYSQL_DATABASE" -o -z "$MYSQL_USER" -o -z "$MYSQL_PASSWORD" -o -z "$READONLY_USER" -o -z "$READONLY_PASSWORD" ]; then
	echo '/pwiki-secrets/dbinfo.sh does not contain the expected environment variables.' >&2
	exit 1
fi
export MYSQL_ROOT_PASSWORD
export MYSQL_DATABASE
export MYSQL_USER
export MYSQL_PASSWORD
cat << EOF > /docker-entrypoint-initdb.d/init.sql
CREATE USER '$READONLY_USER'@'%' IDENTIFIED BY '$READONLY_PASSWORD';
GRANT SELECT ON \`$MYSQL_DATABASE\`.* TO '$READONLY_USER'@'%';
FLUSH PRIVILEGES;
EOF
exec /usr/local/bin/docker-entrypoint.sh mysqld "$@"
