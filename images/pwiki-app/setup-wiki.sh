#!/usr/bin/env bash

set -e
set -x
apt-get install -y sudo gnupg2 wget curl libcurl4-openssl-dev libmcrypt-dev libpng-dev libxml2-dev imagemagick psutils

docker-php-ext-install -j"$(nproc)" curl dom fileinfo gd iconv json mbstring mcrypt mysql session xml zip

# TODO: Also add APC/xcache.

WIKI_UID="$(echo "$WIKI_UIDGID" | cut -d: -f1)"
WIKI_GID="$(echo "$WIKI_UIDGID" | cut -d: -f2)"
if ! echo "$WIKI_UID" | grep -qP '^[0-9]+$'; then
	echo "Invalid UID:GID pair: '$WIKI_UIDGID'" >&2
	exit 1
fi
if ! echo "$WIKI_GID" | grep -qP '^[0-9]+$'; then
	echo "Invalid UID:GID pair: '$WIKI_UIDGID'" >&2
	exit 1
fi
TARGET_CONFIG=/usr/local/etc/php-fpm.d/www.conf
if [ ! -e "$TARGET_CONFIG" ]; then
	echo "Expected config file '$TARGET_CONFIG' not found."
	exit 1
fi

groupadd --gid="$WIKI_GID" pwiki
useradd --uid="$WIKI_UID" --gid=pwiki -s /bin/bash -d /home/pwiki -m pwiki
mkdir -p ~pwiki/www/w ~pwiki/www-private
chmod -R g-rwx,o-rwx ~pwiki
chown -R pwiki:pwiki ~pwiki

cat << EOF > "$TARGET_CONFIG"
[www]
user = pwiki
group = pwiki
listen = 127.0.0.1:9000
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 2
pm.max_spare_servers = 3
EOF
