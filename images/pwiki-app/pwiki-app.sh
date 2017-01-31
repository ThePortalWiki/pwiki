#!/usr/bin/env bash

set -e

if [ -e /pwiki-secrets/no-volume -o -e /home/pwiki/www/w/images/no-volume ]; then
	echo 'Volumes not mounted.' >&2
	exit 1
fi
cp /pwiki-secrets/mediawiki-secrets.php ~pwiki/www-private/mediawiki-secrets.php
chown pwiki:pwiki ~pwiki/www-private/mediawiki-secrets.php

pushd ~pwiki/www/w/maintenance
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
popd

# Unfortunately PHP just leaks memory over time, so we need to restart the workers
# every once in a while.
bash -c 'while true; do php-fpm; done' &
bash -c 'while true; do sleep 6h; pkill php-fpm; done' &

# Run MediaWiki jobs every once in a while.
sudo -u pwiki bash -c 'cd "$HOME/www/w"; while true; do php maintenance/runJobs.php --maxjobs 10; sleep 5m; done' &
wait
