#!/usr/bin/env bash

set -e
set -x

scriptDir="$(cd "$(dirname "${BASH_SOURCE[@]}")" && pwd)"
EXTRA_ROOT="/extra"
WEBROOT="$HOME/www"
WEBROOT_PRIVATE="$HOME/www-private"
MEDIAWIKI_PRODROOT="$WEBROOT/w"
MEDIAWIKI_MAINTENANCE_DIRECTORY="$MEDIAWIKI_PRODROOT/maintenance"
MEDIAWIKI_MAINTENANCE_UPDATE_SCRIPT='update.php'
ROOT_URL='https://theportalwiki.com'
GNUPG_KEYS='https://www.mediawiki.org/keys/keys.txt'

if [ ! -d "$MEDIAWIKI_PRODROOT" ]; then
	echo "Cannot find MediaWiki root '$MEDIAWIKI_PRODROOT'." >&2
	exit 1
fi

if [ ! -d "$EXTRA_ROOT" ]; then
	echo "Cannot find extra root '$EXTRA_ROOT'." >&2
	exit 1
fi

# Sanity check against non-checked-out submodules
if [ ! -e "$EXTRA_ROOT/extensions/RedditThumbnail/README.md" ]; then
	echo 'Submodules not checked out (at least not RedditThumbnail).' >&2
	exit 1
fi

env

if [ -z "$MEDIAWIKI_RELEASE" ]; then
	echo 'MEDIAWIKI_RELEASE not specified.' >&2
	exit 1
fi

BUILD_DIR="$WEBROOT_PRIVATE/.mediawiki-tmp"
rm -rf --one-file-system "$BUILD_DIR"
mkdir --mode=700 "$BUILD_DIR"
# Get the list of point releases before the given one.
# For some reason, mediawiki-x.xx.(something more than 0).tar.gz does not always include
# things that the point-0 release does (extensions), so we just build a kludge from all
# point releases onwards to make sure we don't miss anything.
if ! basename "$MEDIAWIKI_RELEASE" | grep -qP '^mediawiki-[0-9]+\.[0-9]+\.([0-9]+)\.tar\.gz$'; then
	echo "Cannot parse release number from '$MEDIAWIKI_RELEASE'." >&2
	exit 1
fi
releasePoint="$(basename "$MEDIAWIKI_RELEASE" | sed -r 's/^mediawiki-[0-9]+\.[0-9]+\.([0-9]+)\.tar\.gz$/\1/')"
allReleases=()
for point in $(seq 0 "$releasePoint"); do
	allReleases+=("$(dirname "$MEDIAWIKI_RELEASE")/$(basename "$MEDIAWIKI_RELEASE" | sed -r "s/^(mediawiki-[0-9]+\\.[0-9]+\\.)[0-9]+\\.tar\\.gz/\\1$point.tar.gz/")")
done
if [ "${#allReleases[@]}" -eq 0 ]; then
	echo "Could not create release list for '$MEDIAWIKI_RELEASE'." >&2
	exit 1
fi
STAGING_DIR="$BUILD_DIR/staging"
mkdir --mode=700 "$STAGING_DIR"
export GNUPGHOME="$BUILD_DIR/gnupg_tmp"
mkdir --mode=700 "$GNUPGHOME"
cat /extra-keys.asc | gpg --import
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

rm -rf --one-file-system "$MEDIAWIKI_PRODROOT"
mv "$STAGING_DIR" "$MEDIAWIKI_PRODROOT"
rm -rf --one-file-system "$BUILD_DIR"
cp -r "$EXTRA_ROOT"/* "$MEDIAWIKI_PRODROOT/"
chown -R --reference="$WEBROOT" "$MEDIAWIKI_PRODROOT"
chmod -R u+rwX,g-rwx,o-rwx "$MEDIAWIKI_PRODROOT"
