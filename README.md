# Setup for theportalwiki.com

Incomplete because it wasn't open source from the beginning. Sorry.

## Current versions

* MediaWiki: **1.39.3**
* PHP: **8.x**
* MariaDB: **11.0**

## Setup

### Check out repo and submodules

```bash
$ git clone --recursive https://github.com/ThePortalWiki/pwiki

# Or, if you've already cloned the repo prior to reading these instructions:
$ git submodule update --init --recursive
```

### Restore backup and secrets

Ensure the a decrypted backup file is available at this exact path: `/etc/pwiki/pwiki-backup.tar.xz`. How to decrypt a backup file is described below.

### Decrypting backup files

Backup files are of the format `*.tar.xz.gpg.gpg`. The outermost GPG layer is for integrity verification, the innermost layer is for encryption. To both verify and decrypt a backup file, run the following:

```shell
$ echo -n 'encryption key passphrase' | scripts/verify-and-decrypt-backup.sh 'path/to/backup-YYYY-MM-DD.tar.xz.gpg.gpg' > pwiki-backup.tar.xz
```

This will verify the integrity of the given backup file, open the encryption key with the passphrase given on standard input, and write the decrypted backup file to standard output which gets redirected to `pwiki-backup.tar.xz`. This process is best done locally in order to avoid leaving any presence of the decrypted backup encryption private key on the server.

You will then probably want to `scp` the `pwiki-backup.tar.xz` file to the remote host where the wiki should run; see below for more info.

### Run Ansible playbook

Install Ansible on your computer if not done already. Then, run:

```shell
$ resources/ansible/run-ansible.sh
```

This command will fail at some steps that must be done manually, documented below.
Once these manual steps are done, simply re-run Ansible and it will make further progress.
Keep doing this until it succeeds.

#### Dev instance

To set up a dev instance:

- Obtain a domain name (or subdomain) for that instance.
- Point it via DNS to the machine where you want to set up the dev instance.
- Add the relevant information to `resources/ansible/inventory.yml` and `resources/ansible/playbook.yml` in this repository.

Beyond that, the instructions are exactly the same as restoring a backup using the Ansible playbook.

When making changes to test out, simply re-run the Ansible playbook to deploy changes. The Wiki state will be preserved across Ansible runs *as long as the backup file (`/etc/pwiki/pwiki-backup.tar.xz`) is absent*. When the Ansible playbook sees a file at `/etc/pwiki/pwiki-backup.tar.xz`, it will initiate a backup restore proces and then **delete** the `/etc/pwiki/pwiki-backup.tar.xz` file from the filesystem. When this file is absent, this backup restore process is skipped, so the Wiki state is preserved.

## Secrets file format

**You can skip this step if you are restoring/have restored the wiki from a backup**. If not, and you are trying to build a fresh wiki from scratch with new secrets, create a text file at `/etc/pwiki/pwiki-secrets/secrets.sh` with contents as follows:

```bash
MYSQL_ROOT_PASSWORD=something
MYSQL_DATABASE=portalwiki
MYSQL_USER=portalwiki
MYSQL_PASSWORD=something
READONLY_USER=portalwikiread
READONLY_PASSWORD=something
SMTP_EMAIL_PASSWORD=something
MEDIAWIKI_SECRET_KEY=something
RECAPTCHA_PUBLIC_KEY=something
RECAPTCHA_PRIVATE_KEY=something
WINDBOT_USER=WindBOT
WINDBOT_PASSWORD=something
STEAM_API_KEY=something
```

Then remove every other file in `/etc/pwiki/pwiki-secrets/` and run the Ansible playbook again. Ansible will create other files in the same directory that are consumed by other parts of the setup.

## Making new backups

Backups are done by remote machines over SSH. Ansible will automatically create a `pwikibackup` user with its home at `/home/pwikibackup`. Every week, a new database backup will be written to `/home/pwikibackup/backups/<backup date>.sql.xz`.

Ansible will also create a `/home/pwikibackup/backup` script that users may call over SSH to get the newest backup (this `tar`s up both the latest database backup and the whole MediaWiki uploaded files directory). `sshd`'s config file is set to make SSH attempts to the `pwikibackup` user always run this command, such that backups will be output on stdout for any SSH connection. This lets other users with the correct SSH keys create backups by simply caling:

```bash
$ ssh pwikibackup@theportalwiki.com > "backup-$(date '+%Y-%m-%d').tar.xz.gpg.gpg"
```

Backup files are `tar` archives, then compressed with `xz` for compression, then `gpg`-signed-then-encrypted for encryption, and finally `gpg`-signed for integrity. The reason for the double use of `gpg` is such that backups may be integrity-checked without requiring access to the secret key that can decrypt the backup. (The integrity key is never used for authentication; in fact its private half is purposefully checked into this repository.)

Errors will be printed to stderr, and the status code may be reliably used to determine whether the backup was successful. To add users that may perform backups, add their public SSH keys to `resources/backup/users` and re-run Ansible.

### Cryptography details

Backup files may be checked for integrity by checking for a valid GPG signature by the passphrase-less signing key at `resources/backups/signing-key.asc`. This "integrity key" should not be used for any other purpose.

Backups are encrypted with a secret key at `resources/backups/encryption-key.asc`. Its passphrase is split across multiple Portal Wiki staff members, using [Shamir's Secret Sharing Scheme](https://en.wikipedia.org/wiki/Shamir%27s_Secret_Sharing). The particular implementation in use is available at [ThePortalWiki/secret-sharing](https://github.com/ThePortalWiki/secret-sharing). The `scripts/generate-backup-encryption-key.sh` shows how the key was generated.

The key passphrase is split according to a 4:9001 secret-sharing scheme. This means that there are 9001 passphrase fragments out there, and any combination of 4 of them is sufficient to reconstruct the overall passphrase. The 9001st fragment is publicly checked into this repository at `resources/backups/encryption-key.passphrase.9001.ssss-fragment`, effectively rendering making the scheme equivalent to a 3:9000 secret-sharing scheme (the 9001st fragment is checked in just to provide an example fragment format). Staff members are given 1 passphrase fragment when they become staff.

Given 4 fragment files `encryption-key.passphrase.NNNN.ssss-fragment`, here is how to recover the passphrase:

```bash
$ ./scripts/recover-backup-encryption-key-passphrase.sh /path/to/encryption-key.passphrase.*.ssss-fragment
```

The 9001 passphrase fragments are also stored in this repo at `resources/backups/encryption-key-fragments.tar.xz.gpg`. This is a tar file containing all 9001 key fragments, signed and encrypted with the encryption key itself. It is there such that other fragments may be distributed to new staff members without needing to re-generate passphrase fragments (which would annoyingly invalidate the already-distributed key fragments).

### Manual MariaDB backups

*You may skip this section if you used `setup-backups.sh`, as backups are already set up for you. This is about how to make database backups manually.*

Database backups are LZMA-compressed SQL statements.

The `backup-database.sh` script will build a backup container, connect to the running `pwiki-mariab` database container, dump everything to SQL, and compress it with `xz`. The file is moved atomically to the backup file, so there is no risk of copying an incomplete in-progress backup. The backup file will be `chmod`'d `440` with the same UID and GID as its parent directory. It is expected that this user will not change often over time.

The script takes two arguments: the secrets directory, and the full path of the file to back up to.

```bash
$ ./scripts/backup-database.sh /etc/pwiki/pwiki-secrets "/home/pwikibackup/database-backups/$(date '+%Y-%m-%d').sql.xz"
```

### MediaWiki application container

The main containerm `pwiki-app`, is based off [Docker's official `php` container](https://hub.docker.com/_/php/) running in `php-fpm` mode. The MediaWiki installation is stripped down to only its PHP files to minimize image size, and nginx only forwards requests for `*.php` to it. It runs sandboxed with [gVisor](https://gvisor.dev) for extra security. It is automatically built and deployed by the `scripts/upgrade-mediawiki.sh` script documented below.

It also bundles some more functionality to make MediaWiki work properly:

* `imagemagick` for MediaWiki's ImageMagick resizing support
* `msmtp` to send email through Gmail via SMTP
* TODO: Add some opcode caching thing as well

Container build arguments:

* `WIKI_UIDGID`: A numeric `uid:gid` pair which will be used for the user running `php-fpm`.
* `MEDIAWIKI_RELEASE`: The full URL of a MediaWiki release tarball.

It requires two volume mounts:

* `/pwiki-secrets`: Used to get database and SMTP credentials.
* `/home/pwiki/www/w/images/`: Used to drop uploaded files upon upload. This needs to be writable by the user running inside the container, which has its UID/GID defined by the container's build arguments.
