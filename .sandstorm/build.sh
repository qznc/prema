#!/bin/bash
set -euo pipefail
# This script is run in the VM each time you run `vagrant-spk dev`.

cd /opt/app/sqlite3
make
cd ..
dub build -b release -v

exit 0
