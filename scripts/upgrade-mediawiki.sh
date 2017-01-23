#!/usr/bin/env bash

set -e
set -x

scriptDir="$(cd "$(dirname "${BASH_SOURCE[@]}")" && pwd)"
EXTRA_ROOT="$scriptDir/../extra"
FUSECOMPRESS_MOUNT="$scriptDir/fusecompress-mount.sh"
WEBROOT="$HOME/www"
WEBROOT_PRIVATE="$HOME/www-private"
MEDIAWIKI_PRODROOT="$WEBROOT/w"
MEDIAWIKI_PRODROOT_BACKUP="$WEBROOT_PRIVATE/w.old"
MEDIAWIKI_TESTROOT="$WEBROOT_PRIVATE/w.new"
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

# Make sure all submodules are checked out.
pushd "$EXTRA_ROOT"
	git submodule update --init --recursive
popd

if [ ! "$#" -eq 1 ]; then
	echo "Usage: $0 https://releases.wikimedia.org/mediawiki/x.xx/mediawiki-x.xx.xx.tar.gz" >&2
	exit 1
fi

BUILD_DIR="$WEBROOT_PRIVATE/.mediawiki-tmp"
rm -rf --one-file-system "$BUILD_DIR"
mkdir --mode=700 "$BUILD_DIR"
# Get the list of point releases before the given one.
# For some reason, mediawiki-x.xx.(something more than 0).tar.gz does not always include
# things that the point-0 release does (extensions), so we just build a kludge from all
# point releases onwards to make sure we don't miss anything.
currentRelease="$1"
if ! basename "$currentRelease" | grep -qP '^mediawiki-[0-9]+\.[0-9]+\.([0-9]+)\.tar\.gz$'; then
	echo "Cannot parse release number from '$currentRelease'." >&2
	exit 1
fi
currentReleasePoint="$(basename "$currentRelease" | sed -r 's/^mediawiki-[0-9]+\.[0-9]+\.([0-9]+)\.tar\.gz$/\1/')"
allReleases=()
for point in $(seq 0 "$currentReleasePoint"); do
	allReleases+=("$(dirname "$currentRelease")/$(basename "$currentRelease" | sed -r "s/^(mediawiki-[0-9]+\\.[0-9]+\\.)[0-9]+\\.tar\\.gz/\\1$point.tar.gz/")")
done
if [ "${#allReleases[@]}" -eq 0 ]; then
	echo "Could not create release list for '$currentRelease'." >&2
	exit 1
fi
STAGING_DIR="$BUILD_DIR/staging"
mkdir --mode=700 "$STAGING_DIR"
export GNUPGHOME="$BUILD_DIR/gnupg_tmp"
mkdir --mode=700 "$GNUPGHOME"
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
chown -R --reference="$WEBROOT" "$MEDIAWIKI_TESTROOT"
chmod -R u+rwX,g+rwX,o-rwx "$MEDIAWIKI_TESTROOT"

# Swap release directory and set up new release.
"$FUSECOMPRESS_MOUNT" unmount
mv "$MEDIAWIKI_PRODROOT" "$MEDIAWIKI_PRODROOT_BACKUP"
mv "$MEDIAWIKI_TESTROOT" "$MEDIAWIKI_PRODROOT"
"$FUSECOMPRESS_MOUNT" mount

revert_mw() {
	echo 'Reverting release.'
	"$FUSECOMPRESS_MOUNT" unmount
	mv "$MEDIAWIKI_PRODROOT" "$MEDIAWIKI_TESTROOT"
	mv "$MEDIAWIKI_PRODROOT_BACKUP" "$MEDIAWIKI_PRODROOT"
	"$FUSECOMPRESS_MOUNT" mount
	rm -rf --one-file-system "$MEDIAWIKI_TESTROOT"
}

# Run upgrade maintenance script. Needs to be run from its own directory, per MediaWiki manual.
failed=false
pushd "$MEDIAWIKI_MAINTENANCE_DIRECTORY"
	if ! php "$MEDIAWIKI_MAINTENANCE_UPDATE_SCRIPT"; then
		failed=true
	fi
popd
if [ "$failed" == true ]; then
	# Need to run this while outside MEDIAWIKI_MAINTENANCE_DIRECTORY, otherwise the shell
	# will complain that the revert_mw will delete its own current directory.
	revert_mw
	exit 1
fi

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
echo 'Release OK. Proceeding with upgrade.'
rm -rf --one-file-system "$MEDIAWIKI_PRODROOT_BACKUP"
