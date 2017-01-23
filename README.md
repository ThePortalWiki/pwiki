# Setup for theportalwiki.com

Incomplete because it wasn't open source from the beginning. Sorry.

Current MediaWiki version: **1.23.15**

## Upgrading MediaWiki

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
