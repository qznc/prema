#!/bin/bash
set -euo pipefail

mkdir -p /var/prema

touch /var/prema/test
ls -la /var/prema
rm /var/prema/test

cd /opt/app
export LD_LIBRARY_PATH=/opt/app/sqlite3
./prema
