# Setup for theportalwiki.com

Incomplete because it wasn't open source from the beginning. Sorry.

## Current versions

* MediaWiki: **1.23.15**
* PHP: **5.x**
* MariaDB: **10.x**

## Setup

### Check out repo and submodules

```bash
$ git clone --recursive https://github.com/ThePortalWiki/pwiki

# If you've already cloned the repo prior to reading these instructions:
$ git submodule update --init --recursive
```

### Secrets

Put something like this in `/etc/pwiki/pwiki-secrets/dbinfo.sh`:

```bash
MYSQL_ROOT_PASSWORD=something
MYSQL_DATABASE=portalwiki
MYSQL_USER=portalwiki
MYSQL_PASSWORD=something
READONLY_USER=portalwikiread
READONLY_PASSWORD=something
```

Put something like this in `/etc/pwiki/pwiki-secrets/mediawiki-secrets.php`:

```php
<?php
$wgDBname = 'portalwiki';
$wgDBuser = 'portalwiki';
$wgDBpassword = 'something';
$wgSecretKey = 'something';
$wgReCaptchaPublicKey = 'something';
$wgReCaptchaPrivateKey = 'something';
```

Put something like this in `/etc/pwiki/pwiki-secrets/smtp-password`:

```
the_smtp_password_to_portal2wiki_gmail_account
```

### Backups

Backups are done by remote machines over SSH. Running the following as `root`:

```bash
$ ./scripts/setup-backups.sh
```

... will create a `pwikibackup` user with its home at `/home/pwikibackup`. Every week, a new database backup will be written to `/home/pwikibackup/backups/<backup date>.sql.xz`.

This will also create a `/home/pwikibackup/backup` script that users may call over SSH to get the newest backup (this `tar`s up both the latest database backup and the whole MediaWiki uploaded files directory). `sshd`'s config file is set to make this user always run this command, such that backups will be output on stdout for any SSH connection. This lets other machines create backups by simply caling:

```bash
$ ssh pwikibackup@theportalwiki.com > "backup-$(date '+%Y-%m-%d').tar.xz.gpg"
```

Errors will be printed to stderr, and the status code may be reliably used to determine whether the backup was successful. To add users that may perform backups, add their public SSH keys to `resources/backup/users` and re-run `setup-backups.sh`.

#### Crypto details

Backup files may be checked for integrity by checking for a valid GPG signature by the key at `resources/backups/signing-key.asc`. This signing key should not be used for any other purpose.

### MariaDB container

```bash
$ docker build --tag=pwiki-mariadb images/pwiki-mariadb
$ docker run --rm --detach --name=pwiki-mariadb --volume=/etc/pwiki/pwiki-secrets:/pwiki-secrets --volume=/var/lib/mysql-pwiki:/var/lib/mysql pwiki-mariadb
```

### Manual MariaDB backups

*You may skip this section if you used `setup-backups.sh`, as backups are already set up for you. This is about how to make database backups manually.*

Database backups are LZMA-compressed SQL statements.

The `backup-database.sh` script will build a backup container, connect to the running `pwiki-mariab` database container, dump everything to SQL, and compress it with `xz`. The file is moved atomically to the backup file, so there is no risk of copying an incomplete in-progress backup. The backup file will be `chmod`'d `440` with the same UID and GID as its parent directory. It is expected that this user will not change often over time.

The script takes two arguments: the secrets directory, and the full path of the file to back up to.

```bash
$ ./scripts/backup-database.sh /etc/pwiki/pwiki-secrets "/home/pwikibackup/database-backups/$(date '+%Y-%m-%d').sql.xz"
```

### PHP-FPM application container

TODO

## Upgrading MediaWiki

```bash
$ ./scripts/upgrade-mediawiki.sh https://releases.wikimedia.org/mediawiki/x.xx/mediawiki-x.xx.xx.tar.gz
```

This will do the following:
* Download the release
* Verify its GPG signature
* Extract it
* Add in theportalwiki.com-related customizations
* Do the same, but outside the Docker container (for static file serving)
* Re-run the main Docker container
* Ask you whether everything is working at https://theportalwiki.com
* Depending on your answer, either delete the old version or revert to it
