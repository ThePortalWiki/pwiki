#!/usr/bin/env python3

import sys, ssss

fragments = sys.argv[1:]
if len(fragments) < 4:
	print('Must provide at least 4 fragment files as argument.', file=sys.stderr)
	sys.exit(1)

passphrase = ssss.PlaintextToHexSecretSharer.recover_secret([open(f).read() for f in fragments])
print('Passphrase:', passphrase)
