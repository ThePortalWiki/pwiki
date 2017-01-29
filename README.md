# Setup for theportalwiki.com

Incomplete because it wasn't open source from the beginning. Sorry.

## Current versions

* MediaWiki: **1.23.15**
* PHP: TODO
* MariaDB: **10.x**

## Setup

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

Put something like this in `/etc/pwiki/pwiki-secrets/mediawiki-secrets.sh`:

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

```bash
$ docker build --tag=pwiki-mariadb images/pwiki-mariadb
$ docker run --rm --detach --name=pwiki-mariadb --volume=/etc/pwiki/pwiki-secrets:/pwiki-secrets --volume=/var/lib/mysql-pwiki:/var/lib/mysql --publish=127.0.0.1:3666:3306 pwiki-mariadb
```

### PHP-FPM application container


TODO, but it'll probably be something like

```bash
$ docker build --build-arg=WEB_UIDGID="$(stat -c '%u:%g' /home/pwiki/www)" --tag=pwiki-app images/pwiki-app
$ scripts/fusecompress-mount.sh mount
$ docker run --rm --detach --name=pwiki-app --volume=/etc/pwiki/pwiki-secrets:/pwiki-secrets --volume=/home/pwiki/www/w/images:/home/pwiki/www/w/images pwiki-app
```

## Upgrading MediaWiki

TODO: Revamp this

```bash
$ ./scripts/upgrade-mediawiki.sh https://releases.wikimedia.org/mediawiki/x.xx/mediawiki-x.xx.xx.tar.gz
```

This will do the following:
* Download the release
* Verify its GPG signature
* Extract it
* Add in theportalwiki.com-related customizations
* Ask you whether everything is working at https://theportalwiki.com
* Depending on your answer, either delete the old version or revert to it
