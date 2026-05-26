#!/bin/sh
set -e

# Fix data directory permissions for named volume mounts (runs as root before dropping privileges)
mkdir -p /app/data/sessions /app/data/media /app/data/plugins
chown -R openwa:openwa /app/data

# Ensure openwa has a writable home so Chromium 148+ Crashpad can initialise
mkdir -p /home/openwa
chown openwa:openwa /home/openwa

exec gosu openwa dumb-init "$@"
