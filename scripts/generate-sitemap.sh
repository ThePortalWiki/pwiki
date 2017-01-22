#!/usr/bin/env bash

set -e

cd "$HOME/www/w"
php maintenance/generateSitemap.php --fspath ../sitemap --server https://theportalwiki.com --urlpath https://theportalwiki.com/sitemap
