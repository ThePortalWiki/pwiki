#!/usr/bin/env bash

set -euxo pipefail

if [ -e /pwiki/no-volume -o -e /pwiki-secrets/no-volume -o -e /home/pwiki/www/w/images/no-volume ]; then
	echo 'Volumes not mounted.' >&2
	exit 1
fi
PWIKI_DOMAIN="$(cat /pwiki/pwiki.domain)"
PWIKI_NAME="$(cat /pwiki/pwiki.name)"
sed -i "s~WILL_BE_REPLACED_BY_WIKI_DOMAIN~${PWIKI_DOMAIN}~g" /home/pwiki/www/w/LocalSettings.php
sed -i "s~WILL_BE_REPLACED_BY_WIKI_NAME~${PWIKI_NAME}~g"     /home/pwiki/www/w/LocalSettings.php
cp /pwiki-secrets/mediawiki-secrets.php ~pwiki/www-private/mediawiki-secrets.php
cp /pwiki-secrets/smtp-password ~pwiki/www-private/smtp-password
chown -R pwiki:pwiki ~pwiki/www-private

CONTAINER_SUBNET_CIDR="$(ip addr show eth0 | grep -oP 'inet6? \S+' | cut -d' ' -f2)"
sed -i "s~WILL_BE_REPLACED_BY_CONTAINER_NETWORK_CIDR~${CONTAINER_SUBNET_CIDR}~g" /home/pwiki/www/w/LocalSettings.php

pushd ~pwiki/www &>/dev/null
	if [[ -d /patches ]] && [[ "$(ls -1 /patches | grep -P '\.patch$' | wc -l)" -gt 0 ]]; then
		for patch in /patches/*.patch; do
			patch -p1 < "$patch"
		done
	fi
popd &>/dev/null

pushd ~pwiki/www/w/maintenance &>/dev/null
	# Sanity check that the database is up and running.
	if ! sudo -u pwiki php showSiteStats.php; then
		echo "Cannot show site statistics." >&2
		exit 1
	fi
	# Run upgrade maintenance script.
	if ! sudo -u pwiki php update.php --quick; then
		echo "Maintenance script failed." >&2
		exit 1
	fi
	if [[ -f cleanupUsersWithNoId.php ]]; then
		# Run user cleanup script.
		if ! sudo -u pwiki php cleanupUsersWithNoId.php --prefix '*'; then
			echo "cleanupUsersWithNoId.php script failed." >&2
			exit 1
		fi
	fi
	if [[ -f migrateActors.php ]]; then
		# Run actor migration script.
		# This may need re-running:
		# https://www.mediawiki.org/w/index.php?title=Topic:V6ka95f08v2c89yp&topic_showPostId=v6vwyo8mnmjx7v0i#flow-post-v6vwyo8mnmjx7v0i
		if ! sudo -u pwiki php migrateActors.php; then
			echo "migrateActors.php script failed." >&2
			exit 1
		fi
	fi
popd &>/dev/null

# Unfortunately PHP just leaks memory over time, so we need to restart
# the workers every once in a while.
bash -c 'while true; do php-fpm; done' &
bash -c 'while true; do sleep 5h; pkill php-fpm; done' &

# Run MediaWiki jobs every once in a while.
sudo -u pwiki bash -c 'cd "$HOME/www/w"; sleep 3m; while true; do php maintenance/runJobs.php --maxjobs 10; sleep 5m; done' &

# Generate sitemap every once in a while.
sudo -u pwiki bash -c "cd \"\$HOME/www/w\"; sleep 15m; while true; do php maintenance/generateSitemap.php --fspath ../sitemap --server https://$PWIKI_DOMAIN --urlpath https://$PWIKI_DOMAIN/sitemap; sleep 71h; done" &

# Wait indefinitely for all jobs to finish, which they won't.
wait
