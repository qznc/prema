#!/bin/bash
set -euo pipefail
# This script is run in the VM once when you first run `vagrant-spk up`.  It is
# useful for installing system-global dependencies.  It is run exactly once
# over the lifetime of the VM.
#
# This is the ideal place to do things like:
#
export DEBIAN_FRONTEND=noninteractive
#    apt-get install -y nginx nodejs nodejs-legacy python2.7 mysql-server

# Install dmd and dub
wget http://netcologne.dl.sourceforge.net/project/d-apt/files/d-apt.list -O /etc/apt/sources.list.d/d-apt.list
apt-get update
apt-get -y --allow-unauthenticated install --reinstall d-apt-keyring
apt-get update
apt-get -y install dmd-bin libphobos2-dev dub

# Install build dependencies
apt-get -y install libevent-dev libevent-pthreads-2.0-5

# update base system
apt-get -y upgrade

#
# If the packages you're installing here need some configuration adjustments,
# this is also a good place to do that:
#
#    sed --in-place='' \
#            --expression 's/^user www-data/#user www-data/' \
#            --expression 's#^pid /run/nginx.pid#pid /var/run/nginx.pid#' \
#            --expression 's/^\s*error_log.*/error_log stderr;/' \
#            --expression 's/^\s*access_log.*/access_log off;/' \
#            /etc/nginx/nginx.conf

# By default, this script does nothing.  You'll have to modify it as
# appropriate for your application.
exit 0
