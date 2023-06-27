#!/bin/bash

set -euo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[@]}")" && pwd)"
ETC_DIR=/etc/pwiki
LATEST_GOOD_RELEASE_FILE="$ETC_DIR/last-release.url"

if [ ! -f "$LATEST_GOOD_RELEASE_FILE" ]; then
	echo "No 'latest good release' file (expected one at '$LATEST_GOOD_RELEASE_FILE')." >&2
	exit 1
fi
latestReleaseURL="$(cat "$LATEST_GOOD_RELEASE_FILE")"
echo "Restarting MediaWiki from release: $latestReleaseURL" >&2
exec "$scriptDir/setup-mediawiki.sh" --batch "$latestReleaseURL"
