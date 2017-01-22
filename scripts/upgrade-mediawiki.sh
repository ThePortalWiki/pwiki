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

if [ ! "$#" -eq 1 ]; then
	echo "Usage: $0 https://releases.wikimedia.org/mediawiki/x.xx/mediawiki-x.xx.xx.tar.gz" >&2
	exit 1
fi

# Download and verify the release.
BUILD_DIR="$WEBROOT_PRIVATE/.mediawiki-tmp"
rm -rf --one-file-system "$BUILD_DIR"
mkdir --mode=700 "$BUILD_DIR"
pushd "$BUILD_DIR"
	# Download the release.
	wget -O mediawiki.tar.gz "$1"
	# Verify the release.
	wget -O mediawiki.tar.gz.sig "$1.sig"
	export GNUPGHOME="$BUILD_DIR/gnupg_tmp"
	mkdir --mode=700 "$GNUPGHOME"
	wget -O- "$GNUPG_KEYS" | gpg --import
	if ! gpg --verify mediawiki.tar.gz.sig mediawiki.tar.gz; then
		echo "Invalid signature on the release." >&2
		exit 1
	fi
popd

# Extract the release.
MEDIAWIKI_TAR_GZ="$BUILD_DIR/mediawiki.tar.gz"
rm -rf --one-file-system "$MEDIAWIKI_TESTROOT"
mkdir --mode=700 "$MEDIAWIKI_TESTROOT"
tar -xf "$MEDIAWIKI_TAR_GZ" -C "$MEDIAWIKI_TESTROOT" --strip-components=1
rm -rf --one-file-system "$BUILD_DIR"
rm -rf --one-file-system "$MEDIAWIKI_TESTROOT/images"
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
