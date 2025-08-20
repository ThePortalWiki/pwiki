#!/usr/bin/env bash

set -euxo pipefail
shopt -s globstar extglob

if [ "$(id -u)" -ne 0 ]; then
	echo 'This script is meant to run as root.'
	exit 1
fi

scriptDir="$(cd "$(dirname "${BASH_SOURCE[@]}")" && pwd)"
CONTAINER_APP_NAME=pwiki-app
CONTAINER_DATABASE_NAME=pwiki-mariadb
IMAGES_DIR="$scriptDir/../images"
EXTRA_ROOT="$scriptDir/../images/$CONTAINER_APP_NAME/extra"
IMAGE_MOUNT="$scriptDir/image-mount.sh"
MEDIAWIKI_USER=pwiki
MEDIAWIKI_USER_HOME="$(eval echo "~$MEDIAWIKI_USER")"
WEBROOT="$MEDIAWIKI_USER_HOME/www"
WEBROOT_PRIVATE="$MEDIAWIKI_USER_HOME/www-private"
BUILD_DIR="$WEBROOT_PRIVATE/.mediawiki-tmp"
STAGING_DIR="$BUILD_DIR/staging"
MEDIAWIKI_PRODROOT="$WEBROOT/w"
MEDIAWIKI_PRODROOT_BACKUP="$WEBROOT_PRIVATE/w.old"
MEDIAWIKI_TESTROOT="$WEBROOT_PRIVATE/w.new"
MEDIAWIKI_IMAGES_MOUNTPOINT="$MEDIAWIKI_PRODROOT/images"
ETC_DIR=/etc/pwiki
SECRETS_DIR="$ETC_DIR/pwiki-secrets"
LATEST_GOOD_RELEASE_FILE="$ETC_DIR/last-release.url"
ROOT_URL='https://theportalwiki.com'
GNUPG_KEYS='https://www.mediawiki.org/keys/keys.txt'
PHP_FPM_BIND_HOSTPORT=127.0.0.1:3777

if [ ! -d "$MEDIAWIKI_PRODROOT" ]; then
	echo "Cannot find MediaWiki root '$MEDIAWIKI_PRODROOT'." >&2
	exit 1
fi

if [ ! -d "$EXTRA_ROOT" ]; then
	echo "Cannot find extra root '$EXTRA_ROOT'." >&2
	exit 1
fi

if [ "$#" -lt 1 ]; then
	echo "Usage: $0 [--batch] https://releases.wikimedia.org/mediawiki/x.xx/mediawiki-x.xx.xx.tar.gz" >&2
	exit 1
fi
batchMode=false
currentRelease=''
for arg; do
	if [[ "$arg" == '--batch' ]]; then
		batchMode=true
	else
		currentRelease="$arg"
	fi
done
if [[ -z "$currentRelease" ]]; then
	echo "Must specify MediaWiki release." >&2
	exit 1
fi

if ! docker inspect "$CONTAINER_DATABASE_NAME" &>/dev/null; then
	echo "Database container $CONTAINER_DATABASE_NAME does not exist." >&2
	exit 1
fi

# Get the list of point releases before the given one.
# For some reason, mediawiki-x.xx.(something more than 0).tar.gz does not always include
# things that the point-0 release does (extensions), so we just build a kludge from all
# point releases onwards to make sure we don't miss anything.
if ! basename "$currentRelease" | grep -qP '^mediawiki-[0-9]+\.[0-9]+\.([0-9]+)\.tar\.gz$'; then
	echo "Cannot parse release number from '$currentRelease'." >&2
	exit 1
fi
currentReleaseTag="$(basename "$currentRelease" | sed -r 's/^mediawiki-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz$/\1/')"

currentReleasePoint="$(basename "$currentRelease" | sed -r 's/^mediawiki-[0-9]+\.[0-9]+\.([0-9]+)\.tar\.gz$/\1/')"
allReleases=()
for point in $(seq 0 "$currentReleasePoint"); do
	allReleases+=("$(dirname "$currentRelease")/$(basename "$currentRelease" | sed -r "s/^(mediawiki-[0-9]+\\.[0-9]+\\.)[0-9]+\\.tar\\.gz/\\1$point.tar.gz/")")
done
if [ "${#allReleases[@]}" -eq 0 ]; then
	echo "Could not create release list for '$currentRelease'." >&2
	exit 1
fi

# Make sure all submodules are checked out.
pushd "$EXTRA_ROOT"
	sudo -u "$MEDIAWIKI_USER" git submodule update --init --recursive
popd

# Build containers.
docker build --tag="$CONTAINER_DATABASE_NAME" "$IMAGES_DIR/$CONTAINER_DATABASE_NAME"
docker build --build-arg="MEDIAWIKI_RELEASE=$currentRelease" --build-arg="WIKI_UIDGID=$(stat -c '%u:%g' "$WEBROOT")" --tag="$CONTAINER_APP_NAME:$currentReleaseTag" "$IMAGES_DIR/$CONTAINER_APP_NAME"

rm -rf --one-file-system "$BUILD_DIR"
mkdir --mode=700 "$BUILD_DIR" "$STAGING_DIR"
chown -R pwiki:pwiki "$BUILD_DIR" "$STAGING_DIR"
export GNUPGHOME="$BUILD_DIR/gnupg_tmp"
mkdir --mode=700 "$GNUPGHOME"
cat "$IMAGES_DIR/$CONTAINER_APP_NAME/extra-keys.asc" | gpg --import
wget -O- "$GNUPG_KEYS" | gpg --import
pushd "$BUILD_DIR"
	for release in "${allReleases[@]}"; do
		echo "Processing release: '$release'..."
		# Download the release.
		wget -O mediawiki.tar.gz "$release"
		# Verify the release.
		wget -O mediawiki.tar.gz.sig "$release.sig"
		if ! gpg --verify mediawiki.tar.gz.sig mediawiki.tar.gz; then
			echo "Invalid signature on the release." >&2
			exit 1
		fi
		# Extract the release.
		tar -xf mediawiki.tar.gz -C "$STAGING_DIR" --strip-components=1
		rm -rf --one-file-system "$STAGING_DIR/images"
		rm -f mediawiki.tar.gz
	done
popd

rm -rf --one-file-system "$MEDIAWIKI_TESTROOT"
mv "$STAGING_DIR" "$MEDIAWIKI_TESTROOT"
rm -rf --one-file-system "$BUILD_DIR"
cp -r "$EXTRA_ROOT"/* "$MEDIAWIKI_TESTROOT/"
# Replace all PHP files copied from EXTRA_ROOT, as they should be executed from within the container.
set +x
for phpFile in "$MEDIAWIKI_TESTROOT"/**/*.php; do
	if [[ -d "$phpFile" ]]; then
		# Skip directories that end in `.php`.
		continue
	fi
	if [[ ! -f "$phpFile" ]]; then
		# A non-regular-file, non-directory file ending in `.php` is very weird.
		echo "Unexpected non-regular-file non-directory file ending in .php: $phpFile" >&2
		exit 1
	fi
	cat << EOF > "$phpFile"
<?php
die('This file should never be executed from outside the PHP-FPM container. Something is wrong with the wiki setup. If you see this and have no idea what this error message is about, please contact a Wiki staff member.');
EOF
done
set -x
chown -R --reference="$WEBROOT" "$MEDIAWIKI_TESTROOT"
chmod -R u+rwX,g+rwX,o-rwx "$MEDIAWIKI_TESTROOT"

run_app() {
	echo "Running container app with tag '$1'." >&2
	docker run \
		--detach \
		--name="$CONTAINER_APP_NAME" \
		--runtime=runsc \
		--restart=always \
		--link="$CONTAINER_DATABASE_NAME:$CONTAINER_DATABASE_NAME" \
		--volume="$ETC_DIR:/pwiki" \
		--volume="$SECRETS_DIR:/pwiki-secrets" \
		--volume="$MEDIAWIKI_IMAGES_MOUNTPOINT:$MEDIAWIKI_IMAGES_MOUNTPOINT" \
		--publish="$PHP_FPM_BIND_HOSTPORT:9000" \
		"$1"
}

# Determine currently-running release.
noRevertIsOK=''
OLD_TAG="$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_APP_NAME" || true)"
if [ -z "$OLD_TAG" ]; then
	echo "Cannot determine image tag of running '$CONTAINER_APP_NAME' container." >&2
	if [[ "$batchMode" == true ]]; then
		echo 'Continuing anyway because of batch mode.' >&2
		noRevertIsOK='y'
	else
		echo -n 'Continue without revert capability? [y/N] '
		read noRevertIsOK
		noRevertIsOK="$(echo "$noRevertIsOK" | tr '[:upper:]' '[:lower:]')"
		if [ "$noRevertIsOK" != 'y' ]; then
			exit 1
		fi
	fi
fi

# Swap releases.
docker rm -f "$CONTAINER_APP_NAME" || true
"$IMAGE_MOUNT" unmount || true
if [[ -e "$MEDIAWIKI_PRODROOT_BACKUP" ]]; then
	if ! grep -q "$MEDIAWIKI_PRODROOT_BACKUP" /proc/mounts; then
		rm -rf --one-file-system "$MEDIAWIKI_PRODROOT_BACKUP"
	fi
fi
mv "$MEDIAWIKI_PRODROOT" "$MEDIAWIKI_PRODROOT_BACKUP"
mv "$MEDIAWIKI_TESTROOT" "$MEDIAWIKI_PRODROOT"
"$IMAGE_MOUNT" mount
run_app "$CONTAINER_APP_NAME:$currentReleaseTag"

revert_mw() {
	echo 'Reverting release.'
	docker rm -f "$CONTAINER_APP_NAME" || true
	"$IMAGE_MOUNT" unmount
	mv "$MEDIAWIKI_PRODROOT" "$MEDIAWIKI_TESTROOT"
	mv "$MEDIAWIKI_PRODROOT_BACKUP" "$MEDIAWIKI_PRODROOT"
	"$IMAGE_MOUNT" mount
	run_app "$OLD_TAG"
	rm -rf --one-file-system "$MEDIAWIKI_TESTROOT"
}

if [[ "$batchMode" == true ]]; then
	echo "Setup complete: $ROOT_URL"
else
	if [ "$noRevertIsOK" != 'y' ]; then
		# Manual testing of new release.
		echo "Please try out the new release at '$ROOT_URL'."
		releaseOK='invalid'
		while [ "$releaseOK" != 'y' -a "$releaseOK" != 'n' -a -n "$releaseOK" ]; do
			echo -n 'Good to upgrade? [y/N] '
			read releaseOK
			releaseOK="$(echo "$releaseOK" | tr '[:upper:]' '[:lower:]')"
		done
		if [ "$releaseOK" != 'y' ]; then
			revert_mw
			exit 0
		fi
	fi
	echo 'Release OK. Proceeding with upgrade.'
fi
echo "$currentRelease" > "$LATEST_GOOD_RELEASE_FILE"
rm -rf --one-file-system "$MEDIAWIKI_PRODROOT_BACKUP"
