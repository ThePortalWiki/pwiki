#!/usr/bin/env bash

set -euxo pipefail

apt-get install -y sudo gnupg2 wget curl libcurl4-openssl-dev libmcrypt-dev libpng-dev libzip-dev libxml2-dev libonig-dev imagemagick psutils procps msmtp ffmpeg

for ext in curl dom fileinfo gd iconv intl mbstring mysqli session xml zip; do
	if ! docker-php-ext-install -j"$(nproc)" "$ext"; then
		echo "Failed to install extension: $ext" >&2
		exit 1
	fi
done
pear install mail
pear install net_smtp

# Get the latest APCu version number from https://pecl.php.net/package/APCU
pecl install -f apcu-5.1.22 </dev/null
docker-php-ext-enable apcu --ini-name 10-docker-php-ext-apcu.ini

# PHP settings
mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
echo "upload_max_filesize = $(( 32 * 1024 * 1024 ))" >> "$PHP_INI_DIR/conf.d/php-wiki.ini"
echo "post_max_size = $(( 33 * 1024 * 1024 ))" >> "$PHP_INI_DIR/conf.d/php-wiki.ini"

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
PHPFPM_CONFIG=/usr/local/etc/php-fpm.d/www.conf
if [ ! -e "$PHPFPM_CONFIG" ]; then
	echo "Expected config file '$PHPFPM_CONFIG' not found."
	exit 1
fi
PHP_SENDMAIL_CONFIG=/usr/local/etc/php/conf.d/wiki-sendmail.ini

groupadd --gid="$WIKI_GID" pwiki
useradd --uid="$WIKI_UID" --gid=pwiki -s /bin/bash -d /home/pwiki -m pwiki
mkdir -p ~pwiki/www/w ~pwiki/www-private
MSMTP_CONFIG="$(eval echo '~pwiki/www-private/msmtp.conf')"

cat << EOF > "$PHPFPM_CONFIG"
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

cat << EOF > "$MSMTP_CONFIG"
# Accounts will inherit settings from this section
defaults
auth             on
tls              on
tls_certcheck    on
tls_trust_file   /etc/ssl/certs/ca-certificates.crt

account        portal2wiki
host           smtp.gmail.com
port           465
from           portal2wiki@gmail.com
user           portal2wiki@gmail.com
passwordeval   "cat /home/pwiki/www-private/smtp-password"

account default : portal2wiki
EOF

# msmtp isn't actually used by PHP anymore, so the above config is only useful
# for manual msmtp invocations from the command-line to test email sending.
# Uncommenting the following line will make PHP use SMTP:
# echo "sendmail_path = \"$(which msmtp) -C $MSMTP_CONFIG -t\"" > "$PHP_SENDMAIL_CONFIG"

chmod -R g-rwx,o-rwx ~pwiki
chown -R pwiki:pwiki ~pwiki
