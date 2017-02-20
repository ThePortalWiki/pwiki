#!/usr/bin/env bash

set -euo pipefail

repoDir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backupResourcesDir="$repoDir/resources/backups"

# Make sure all submodules are checked out.
pushd "$repoDir" &> /dev/null
	sudo -u "$(stat -c '%U' .)" git submodule update --init --recursive
popd &> /dev/null

exec "$backupResourcesDir/recover-encryption-key-passphrase.py" "$@"
