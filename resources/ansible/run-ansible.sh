#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
exec ansible-playbook -i inventory.yml playbook.yml "$@"
