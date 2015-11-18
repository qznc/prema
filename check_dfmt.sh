#!/bin/bash
# This is intended to be run from a git pre-commit hook like:
# git diff --cached --name-only $against | grep "\.d\$" | ./check_dfmt.sh || exit 1
# Requires dfmt in $PATH

set -eu
while read line
do
	dfmt "$line" | diff -u "$line" -
done
