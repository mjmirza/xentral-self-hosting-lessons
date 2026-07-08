#!/usr/bin/env bash
#
# deploy-openxe.sh
#
# Reproducible recipe to stand up a self-hosted OpenXE (the community fork of the
# old open-source Xentral) with Docker and Caddy TLS.
#
# IMPORTANT context before you run this. OpenXE is the PREVIOUS generation of
# Xentral. Its API uses HTTP Digest auth and will NOT work with any connector
# built for the modern Xentral cloud API (Bearer Personal Access Token, v1/v2/v3).
# If your goal was a self-hosted target for a modern Xentral MCP, this will not
# serve it. See the README in this repo for the full reasoning.
#
# No secrets are baked in. Database passwords are generated at runtime. Set your
# own domain in the DOMAIN variable below.
#
# Tested shape. Ubuntu 24.04, ~4 GB RAM plus swap, Docker + compose plugin.

set -uo pipefail

# ---- configure this ----
DOMAIN="${DOMAIN:-your.domain.example}"     # a DNS A record must point at this box first
OPENXE_DIR="${OPENXE_DIR:-/opt/openxe}"
APP_PORT="${APP_PORT:-8081}"                 # bound to loopback, fronted by Caddy
# ------------------------

log() { printf '[deploy-openxe] %s\n' "$*"; }

# 1. clone OpenXE
if [ ! -d "$OPENXE_DIR/.git" ]; then
  git clone --depth 1 https://github.com/OpenXE-org/OpenXE.git "$OPENXE_DIR"
fi
cd "$OPENXE_DIR" || exit 1

# 2. generate strong DB credentials on the box (never printed, never committed)
DBPASS="$(openssl rand -hex 24)"
ROOTPASS="$(openssl rand -hex 24)"

# 3. the DB connection OpenXE reads (gitignored by OpenXE). $this is PHP, kept literal.
cat > conf/user.inc.php <<PHP
<?php
\$this->WFdbhost = 'mysql';
\$this->WFdbport = 3306;
\$this->WFdbname = 'openxe';
\$this->WFdbuser = 'openxe';
\$this->WFdbpass = '${DBPASS}';
PHP
chmod 640 conf/user.inc.php
grep -qx 'conf/user.inc.php' .dockerignore 2>/dev/null || echo 'conf/user.inc.php' >> .dockerignore

# 4. harden the compose. app on loopback only, DB port never public.
#    Docker publishes ports past a host firewall, so bind DB to loopback explicitly.
sed -i "s|\"8081:80\"|\"127.0.0.1:${APP_PORT}:80\"|" docker-compose.yml
sed -i 's|"3306:3306"|"127.0.0.1:3306:3306"|' docker-compose.yml
cat > docker-compose.override.yml <<YML
services:
  mysql:
    environment:
      MYSQL_ROOT_PASSWORD: "${ROOTPASS}"
      MYSQL_PASSWORD: "${DBPASS}"
  app_init:
    volumes: !reset
      - ${OPENXE_DIR}/conf/user.inc.php:/var/www/html/conf/user.inc.php:ro
  app:
    volumes: !reset
      - ${OPENXE_DIR}/conf/user.inc.php:/var/www/html/conf/user.inc.php:ro
    restart: unless-stopped
YML

# 5. THE FIX THAT SAVES AN HOUR. php:8.1-apache moved to Debian 13 (trixie), but
#    OpenXE pins Debian 12 (bookworm) package versions. Pin the web stage to bookworm.
sed -i 's|^FROM php:8.1-apache as web_server|FROM php:8.1-apache-bookworm as web_server|' docker/Dockerfile

# 6. build + up. app_init runs the DB migration once, then app serves on loopback.
docker compose build app
docker compose up -d app
log "OpenXE building/migrating. app will serve on 127.0.0.1:${APP_PORT}"

# 7. Caddy in front for automatic TLS. Requires a DNS A record for $DOMAIN -> this box.
cat > /etc/caddy/Caddyfile <<CADDY
${DOMAIN} {
	encode gzip
	reverse_proxy 127.0.0.1:${APP_PORT} {
		header_up X-Forwarded-Proto https
	}
}
CADDY
systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true
log "Caddy configured for ${DOMAIN}. It obtains a cert once DNS resolves to this box."

# 8. set the admin password. OpenXE checks the passwordhash column (bcrypt),
#    NOT the legacy password column. Run this AFTER the stack is up.
#    Replace CHANGE_ME with your chosen password, then run:
#
#      HASH=$(docker exec openxe-app-1 php -r 'echo password_hash($argv[1], PASSWORD_BCRYPT);' "CHANGE_ME")
#      docker exec openxe-mysql-1 mysql -uopenxe -p"$DBPASS" openxe -e \
#        "UPDATE user SET passwordhash='$HASH', password='', passwordmd5='', salt='', passwordsha512='', activ=1 WHERE id=1;"
#
#    Then log in at https://${DOMAIN}/ with username admin and that password.

log "Done. Remember: OpenXE is the OLD Xentral generation and does not speak the modern API."
