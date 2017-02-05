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

### MariaDB container

```bash
$ docker build --tag=pwiki-mariadb images/pwiki-mariadb
$ docker run --rm --detach --name=pwiki-mariadb --volume=/etc/pwiki/pwiki-secrets:/pwiki-secrets --volume=/var/lib/mysql-pwiki:/var/lib/mysql pwiki-mariadb
```

### MariaDB backup

Database backups are LZMA-compressed SQL statements.

The `backup-database.sh` script will build a backup container, connect to the running `pwiki-mariab` database container, dump everything to SQL, and compress it with `xz`. The file is moved atomically to the backup file, so there is no risk of copying an incomplete in-progress backup. The backup file will be `chmod`'d `440` with the same UID and GID as its parent directory. It is expected that this user will not change often over time.

The script takes two arguments: the secrets directory, and the full path of the file to back up to.

```bash
$ ./scripts/backup-database.sh /etc/pwiki/pwiki-secrets "/var/lib/mysql-pwiki-backups/$(date '+%Y-%m-%d').sql.xz"
```

A sample `crontab` entry to automate backups is provided in `crontab/root.crontab`.

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
