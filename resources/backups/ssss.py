# Hacky way to import the secret-sharing modules without installing them. It's dirty. Whatever.
import os, sys, inspect
scriptDir = os.path.realpath(os.path.abspath(os.path.split(inspect.getfile(inspect.currentframe()))[0]))
secretSharingModuleDir = os.path.join(scriptDir, 'secret-sharing')
utilityBeltModuleDir = os.path.join(scriptDir, 'python-utilitybelt')
sys.path.extend((secretSharingModuleDir, utilityBeltModuleDir))

from secretsharing import *
