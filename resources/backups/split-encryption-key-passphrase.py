#!/usr/bin/env python3

import ssss, sys

passphrase = sys.stdin.read()

fragmentsData = ssss.PlaintextToHexSecretSharer.split_secret(passphrase, 4, 9001)
for n, fragmentData in enumerate(fragmentsData):
	with open('encryption-key.passphrase.{n:0>4}.ssss-fragment'.format(n=n+1), 'w') as f:
		f.write(fragmentData)
