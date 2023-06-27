#!/usr/bin/env bash

set -euo pipefail

repoDir="$(dirname "${BASH_SOURCE[0]}")/.."
imagesDir="$repoDir/images"
socketFile='/run/wiki.sock'
botContainerName='pwiki-bot'

SECRETS_DIR="$1"
if [ ! -e "$SECRETS_DIR/botConfig.py" ]; then
	echo "Secrets directory '$SECRETS_DIR' does not contain the expected botConfig.py." >&2
	exit 1
fi
if [ ! -e "$socketFile" ]; then
    echo "Socket file at $socketFile does not exist (is nginx running?), bailing out." >&2
    exit 1
fi

docker build --quiet           \
    --tag="$botContainerName"  \
    "$imagesDir/$botContainerName" > /dev/null

docker rm -f "$botContainerName" &>/dev/null || true

docker run --rm \
    --name="$botContainerName"         \
    --runtime=runsc                    \
    --volume="$socketFile:/wiki.sock"  \
    --volume="$SECRETS_DIR/botConfig.py:/botConfig/botConfig.py"  \
    "$botContainerName"
