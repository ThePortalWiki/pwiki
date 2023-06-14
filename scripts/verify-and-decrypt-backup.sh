#!/bin/bash

set -euo pipefail

SIGNING_KEY_FINGERPRINT='1FA1E516E443B624F9B49599C3C4164B2909D259'

if [[ "$#" != 1 ]]; then
	echo "Usage: echo -n backup_decryption_key_passphrase | $0 path/to/backup-YYYY-MM-DD.tar.xz.gpg.gpg > pwiki-backup.tar.xz" >&2
	exit 1
fi

decryptionKeyPassphrase="$(</dev/stdin)"

backupFile="$1"
if [[ ! -f "$backupFile" ]]; then
	echo "No such file: $backupFile" >&2
	exit 1
fi
if ! echo "$backupFile" | grep -q '\.tar\.xz\.gpg\.gpg$'; then
	echo "Backup file '$backupFile' is in the wrong format (expecting .tar.xz.gpg.gpg.)" >&2
	exit 1
fi

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repoDir="$scriptDir/.."
signingKey="$repoDir/resources/backups/signing-key.asc"
encryptionKey="$repoDir/resources/backups/encryption-key.asc"

echo "Importing keys into temporary GnuPG directory..." >&2
tmpDir="$(mktemp -d)"
run_gpg() {
	GNUPGHOME="$tmpDir/.gnupg" gpg --batch --yes "$@"
}
export GNUPGHOME="$tmpDir/.gnupg"
mkdir -m700 "$GNUPGHOME"
echo -n "$decryptionKeyPassphrase" | run_gpg --passphrase-fd 0 --pinentry-mode loopback --import "$encryptionKey" 2>/dev/null || (echo 'GnuPG error while importing encryption key; perhaps the passphrase is wrong?' >&2; exit 1)
run_gpg --import < "$signingKey" 2>/dev/null || (echo 'GnuPG error while importing signing key.' >&2; exit 1)

echo "Verifying integrity and decrypting backup file..." >&2
run_gpg \
	--status-fd 3 \
	--decrypt \
	< "$backupFile" \
	2> /dev/null \
	3> "$tmpDir/outer.statusfd" \
	| run_gpg \
		--status-fd 3 \
		--passphrase-fd 4 \
		--pinentry-mode loopback \
		--decrypt \
		3> "$tmpDir/inner.statusfd" \
		4< <(echo -n "$decryptionKeyPassphrase") \
		> "$tmpDir/backup.tar.xz" \
	|| (echo 'Decryption failed.' >&2 && rm -r "$tmpDir" && exit 1)

if ! grep -q "VALIDSIG $SIGNING_KEY_FINGERPRINT" "$tmpDir/outer.statusfd"; then
	echo "Backup file $backupFile was not signed properly." >&2
	rm -r "$tmpDir"
	exit 1
fi
echo 'Backup file is properly signed and decrypted successfully. Writing out compressed backup...' >&2
cat "$tmpDir/backup.tar.xz"
rm -r "$tmpDir"
echo "All done." >&2
