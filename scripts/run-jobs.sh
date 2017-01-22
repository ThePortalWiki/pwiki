#!/usr/bin/env bash

set -e

cd "$HOME/www/w"
php maintenance/runJobs.php --maxjobs 10
