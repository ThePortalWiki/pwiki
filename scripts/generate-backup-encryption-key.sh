#!/usr/bin/env bash

set -euxo pipefail

repoDir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backupResourcesDir="$repoDir/resources/backups"

# Make sure all submodules are checked out.
pushd "$repoDir" &> /dev/null
	sudo -u "$(stat -c '%U' .)" git submodule update --init --recursive
popd &> /dev/null

tmpDir="$(mktemp -d)"
export GNUPGHOME="$tmpDir/.gnupg"
mkdir -m700 "$GNUPGHOME"
echo 'Generating and splitting passphrase...' >&2
PASSPHRASE="$(python3 -c 'import string, random; print("".join(random.SystemRandom().choice(string.ascii_uppercase + string.ascii_lowercase + string.digits) for _ in range(192)))')"
passphraseFile="$tmpDir/passphrase"
tr -d '\n' << EOF > "$passphraseFile"
$PASSPHRASE
EOF
KEY_EMAIL='staff@theportalwiki.com'
NUM_FRAGMENTS=9001
fragmentsDir="$tmpDir/encryption-key.passphrase.fragments"
mkdir -m700 "$fragmentsDir"
pushd "$fragmentsDir" &> /dev/null
	echo -n "$PASSPHRASE" | "$backupResourcesDir/split-encryption-key-passphrase.py"
popd &> /dev/null
echo 'Passphrase split, generating key...' >&2
cat << EOF > "$tmpDir/gpg-keyspec"
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Subkey-Type: RSA
Subkey-Length: 4096
Subkey-Usage: encrypt
Name-Real: Portal Wiki backup encryption key
Name-Comment: Key used for backup encryption; see https://github.com/ThePortalWiki/pwiki for recovery instructions
Name-Email: $KEY_EMAIL
Expire-Date: 0
Passphrase: $PASSPHRASE
%commit
EOF
gpg --batch --no-tty --yes --generate-key "$tmpDir/gpg-keyspec"
echo 'Key generated. Creating encrypted+signed fragment archive.' >&2
tar --create --file=- --xz --one-file-system --directory="$(dirname "$fragmentsDir")" "$(basename "$fragmentsDir")" | gpg --batch --quiet --no-tty --yes --pinentry-mode=loopback --passphrase-file="$passphraseFile" --encrypt --recipient="$KEY_EMAIL" --sign --local-user="$KEY_EMAIL" > "$backupResourcesDir/$(basename "$fragmentsDir").tar.xz.gpg"
echo 'Moving files into repo directory.' >&2
cat << EOF > "$backupResourcesDir/encryption-key.asc"
This GnuPG private key is protected by a passphrase which is
split into many fragments using Shamir's Secret Sharing Scheme.
Please read this repository's README.md file to find out how to
recover its passphrase.
EOF
gpg --batch --export-secret-keys --no-tty --yes --pinentry-mode=loopback --passphrase-file="$passphraseFile" --armor >> "$backupResourcesDir/encryption-key.asc"
echo 'This is the public part for encryption-key.asc.' > "$backupResourcesDir/encryption-key.pub.asc"
gpg --batch --export --armor "$KEY_EMAIL" >> "$backupResourcesDir/encryption-key.pub.asc"
cp "$fragmentsDir/encryption-key.passphrase.$NUM_FRAGMENTS.ssss-fragment" "$backupResourcesDir/"
echo 'All done.' >&2
echo '--------------------------------------------------------' >&2
echo 'Passphrase (DO NOT WRITE THIS DOWN SOMEWHERE PERMANENT):' >&2
echo "$PASSPHRASE" >&2
echo '--------------------------------------------------------' >&2
# FIXME rm -rf "$tmpDir"
