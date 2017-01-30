# Setup for theportalwiki.com

Incomplete because it wasn't open source from the beginning. Sorry.

## Current versions

* MediaWiki: **1.23.15**
* PHP: TODO
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

### MariaDB container

TODO: Set up backup container too so that there's no need to publish a port here.

```bash
$ docker build --tag=pwiki-mariadb images/pwiki-mariadb
$ docker run --rm --detach --name=pwiki-mariadb --volume=/etc/pwiki/pwiki-secrets:/pwiki-secrets --volume=/var/lib/mysql-pwiki:/var/lib/mysql --publish=127.0.0.1:3666:3306 pwiki-mariadb
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
