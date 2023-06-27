#!/bin/bash

set -euo pipefail

source /etc/pwiki/pwiki-secrets/secrets.sh

generate_dbinfo() {
	cat <<EOF
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_DATABASE=$MYSQL_DATABASE
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
READONLY_USER=$READONLY_USER
READONLY_PASSWORD=$READONLY_PASSWORD
EOF
}

generate_mediawiki_secrets() {
	cat <<EOF
<?php
\$wgDBname = '$MYSQL_DATABASE';
\$wgDBuser = '$MYSQL_USER';
\$wgDBpassword = '$MYSQL_PASSWORD';
\$wgSecretKey = '$MEDIAWIKI_SECRET_KEY';
\$wgReCaptchaPublicKey = '$RECAPTCHA_PUBLIC_KEY';
\$wgReCaptchaPrivateKey = '$RECAPTCHA_PRIVATE_KEY';
\$smtpEmailPassword = '$SMTP_EMAIL_PASSWORD';
EOF
}

generate_smtp_password() {
	echo -n "$SMTP_EMAIL_PASSWORD"
}

generate_bot_config() {
	cat <<EOF
# -*- coding: utf-8 -*-

config = {
        'api': 'http://127.0.0.1:3333/w/api.php', # Wiki API URL
        'steamAPI': '$STEAM_API_KEY', # Steam API key
        'username': '$WINDBOT_USER', # Username
        'password': '$WINDBOT_PASSWORD', # Password
        'maxrequests': 16, # Max PageRequests to process per run
        'rcidrate': 50, # Edit RCID every n edits
        'freshnessThreshold': 300, # In seconds
        'pagePasses': 8, # Maximum number of parsing/filtering passes
        'filterPasses': 64, # Maximum number of times to run a fitler on a filtering pass
        'tempPrefix': 'pwiki', # Prefix used for naming temporary files
        'editCreateRetries': 5,
        'pages': {
                'filters': 'User:$WINDBOT_USER/Filters', # Filters page
                'blacklist': 'User:$WINDBOT_USER/Blacklist', # Blacklist
                'pagerequests': 'User:$WINDBOT_USER/PageRequests', # PageRequests
                'pagerequestsforce': 'User:$WINDBOT_USER/PageRequestsForce', # PageRequests bypassing blacklist
                'rcid': 'User:$WINDBOT_USER/RCID', # RCID page
                'editcount': 'User:$WINDBOT_USER/EditCount' # Edit count page
        }
}

EOF
}

for arg; do
	if [[ "$arg" == dbinfo.sh ]]; then
		generate_dbinfo > /etc/pwiki/pwiki-secrets/dbinfo.sh
	elif [[ "$arg" == mediawiki-secrets.php ]]; then
		generate_mediawiki_secrets > /etc/pwiki/pwiki-secrets/mediawiki-secrets.php
	elif [[ "$arg" == smtp-password ]]; then
		generate_smtp_password > /etc/pwiki/pwiki-secrets/smtp-password
	elif [[ "$arg" == botConfig.py ]]; then
		generate_bot_config > /etc/pwiki/pwiki-secrets/botConfig.py
	else
		echo "Unknown secrets filename: $arg" >&2
		exit 1
	fi
done
chown --reference=/etc/pwiki/pwiki-secrets /etc/pwiki/pwiki-secrets/*
chmod 600 /etc/pwiki/pwiki-secrets/*
