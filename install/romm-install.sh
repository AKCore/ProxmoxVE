#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: AKCore
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://romm.app/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

get_latest_release() {
  curl -fsSL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}

DOCKER_LATEST_VERSION=$(get_latest_release "moby/moby")
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")

msg_info "Installing Docker $DOCKER_LATEST_VERSION"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -fsSL https://get.docker.com)
$STD systemctl enable docker
msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

msg_info "Installing Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
msg_ok "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"

msg_info "Installing RomM"
mkdir -p /opt/romm/{config,library,assets,resources,redis-data}

msg_info "Creating Platform Folders (EmulatorJS Supported)"
mkdir -p /opt/romm/library/roms/{3do,amiga,arcade,atari2600,atari5200,atari7800,jaguar,lynx,c64,colecovision,dos,flash,neo-geo-pocket,neo-geo-pocket-color,n64,nes,famicom,nds,gb,gbc,gba,pc-fx,psx,psp,sega32,segacd,gamegear,sms,genesis,saturn,snes,sfam,tg16,virtualboy,wonderswan,wonderswan-color}
msg_ok "Created Platform Folders"

DB_ROOT_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
AUTH_SECRET=$(openssl rand -hex 32)

cat <<EOF >/opt/romm/docker-compose.yml
version: "3"

volumes:
  mysql_data:

services:
  romm:
    image: rommapp/romm:latest
    container_name: romm
    restart: unless-stopped
    environment:
      - DB_HOST=romm-db
      - DB_NAME=romm
      - DB_USER=romm-user
      - DB_PASSWD=${DB_PASS}
      - ROMM_AUTH_SECRET_KEY=${AUTH_SECRET}
      - IGDB_CLIENT_ID=
      - IGDB_CLIENT_SECRET=
      - SCREENSCRAPER_USER=
      - SCREENSCRAPER_PASSWORD=
      - RETROACHIEVEMENTS_API_KEY=
      - STEAMGRIDDB_API_KEY=
      - MOBYGAMES_API_KEY=
      - HASHEOUS_API_ENABLED=true
      - PLAYMATCH_API_ENABLED=true
      - LAUNCHBOX_API_ENABLED=true
    volumes:
      - /opt/romm/resources:/romm/resources
      - /opt/romm/redis-data:/redis-data
      - /opt/romm/library:/romm/library
      - /opt/romm/assets:/romm/assets
      - /opt/romm/config:/romm/config
    ports:
      - 8080:8080
    depends_on:
      romm-db:
        condition: service_healthy
        restart: true

  romm-db:
    image: mariadb:latest
    container_name: romm-db
    restart: unless-stopped
    environment:
      - MARIADB_ROOT_PASSWORD=${DB_ROOT_PASS}
      - MARIADB_DATABASE=romm
      - MARIADB_USER=romm-user
      - MARIADB_PASSWORD=${DB_PASS}
    volumes:
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 30s
      start_interval: 10s
      interval: 10s
      timeout: 5s
      retries: 5
EOF

{
  echo "RomM Credentials"
  echo "================"
  echo "Database Root Password: $DB_ROOT_PASS"
  echo "Database User: romm-user"
  echo "Database Password: $DB_PASS"
  echo "Database Name: romm"
  echo "Auth Secret Key: $AUTH_SECRET"
  echo ""
  echo "Directories:"
  echo "  Library (ROMs): /opt/romm/library"
  echo "  Assets (saves): /opt/romm/assets"
  echo "  Config: /opt/romm/config"
  echo ""
  echo "Platform Folders (EmulatorJS Supported):"
  echo "  3do, amiga, arcade, atari2600, atari5200, atari7800,"
  echo "  jaguar, lynx, c64, colecovision, dos, flash,"
  echo "  neo-geo-pocket, neo-geo-pocket-color, n64, nes, famicom,"
  echo "  nds, gb, gbc, gba, pc-fx, psx, psp, sega32, segacd,"
  echo "  gamegear, sms, genesis, saturn, snes, sfam, tg16,"
  echo "  virtualboy, wonderswan, wonderswan-color"
} >/opt/romm/romm.creds

cat <<'SETUP_SCRIPT' >/opt/romm/romm-setup.sh
#!/usr/bin/env bash

# RomM Setup Script
# This script helps configure optional API keys for metadata providers

COMPOSE_FILE="/opt/romm/docker-compose.yml"

echo "============================================"
echo "       RomM Metadata Provider Setup"
echo "============================================"
echo ""
echo "This script will help you configure optional API keys"
echo "for enhanced metadata fetching. All fields are optional."
echo "Press Enter to skip any field."
echo ""

read -r -p "IGDB Client ID: " IGDB_CLIENT_ID
read -r -p "IGDB Client Secret: " IGDB_CLIENT_SECRET
read -r -p "ScreenScraper Username: " SCREENSCRAPER_USER
read -r -p "ScreenScraper Password: " SCREENSCRAPER_PASSWORD
read -r -p "RetroAchievements API Key: " RETROACHIEVEMENTS_API_KEY
read -r -p "SteamGridDB API Key: " STEAMGRIDDB_API_KEY
read -r -p "MobyGames API Key: " MOBYGAMES_API_KEY

if [[ -n "$IGDB_CLIENT_ID" ]]; then
  sed -i "s/IGDB_CLIENT_ID=.*/IGDB_CLIENT_ID=${IGDB_CLIENT_ID}/" "$COMPOSE_FILE"
fi
if [[ -n "$IGDB_CLIENT_SECRET" ]]; then
  sed -i "s/IGDB_CLIENT_SECRET=.*/IGDB_CLIENT_SECRET=${IGDB_CLIENT_SECRET}/" "$COMPOSE_FILE"
fi
if [[ -n "$SCREENSCRAPER_USER" ]]; then
  sed -i "s/SCREENSCRAPER_USER=.*/SCREENSCRAPER_USER=${SCREENSCRAPER_USER}/" "$COMPOSE_FILE"
fi
if [[ -n "$SCREENSCRAPER_PASSWORD" ]]; then
  sed -i "s/SCREENSCRAPER_PASSWORD=.*/SCREENSCRAPER_PASSWORD=${SCREENSCRAPER_PASSWORD}/" "$COMPOSE_FILE"
fi
if [[ -n "$RETROACHIEVEMENTS_API_KEY" ]]; then
  sed -i "s/RETROACHIEVEMENTS_API_KEY=.*/RETROACHIEVEMENTS_API_KEY=${RETROACHIEVEMENTS_API_KEY}/" "$COMPOSE_FILE"
fi
if [[ -n "$STEAMGRIDDB_API_KEY" ]]; then
  sed -i "s/STEAMGRIDDB_API_KEY=.*/STEAMGRIDDB_API_KEY=${STEAMGRIDDB_API_KEY}/" "$COMPOSE_FILE"
fi
if [[ -n "$MOBYGAMES_API_KEY" ]]; then
  sed -i "s/MOBYGAMES_API_KEY=.*/MOBYGAMES_API_KEY=${MOBYGAMES_API_KEY}/" "$COMPOSE_FILE"
fi

echo ""
echo "Configuration updated. Restarting RomM..."
cd /opt/romm
docker compose down
docker compose up -d

echo ""
echo "============================================"
echo "Setup complete!"
echo ""
echo "Access RomM at: http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo "ROM Library Location: /opt/romm/library/roms/"
echo ""
echo "Pre-created Platform Folders (EmulatorJS Supported):"
echo "  3do, amiga, arcade, atari2600, atari5200, atari7800,"
echo "  jaguar, lynx, c64, colecovision, dos, flash,"
echo "  neo-geo-pocket, neo-geo-pocket-color, n64, nes, famicom,"
echo "  nds, gb, gbc, gba, pc-fx, psx, psp, sega32, segacd,"
echo "  gamegear, sms, genesis, saturn, snes, sfam, tg16,"
echo "  virtualboy, wonderswan, wonderswan-color"
echo ""
echo "For folder structure details, see:"
echo "https://docs.romm.app/latest/Getting-Started/Folder-Structure/"
echo "============================================"
SETUP_SCRIPT

chmod +x /opt/romm/romm-setup.sh

cd /opt/romm
$STD docker compose up -d

msg_info "Waiting for RomM to start"
sleep 10
timeout 120 bash -c 'until docker ps | grep -q "romm.*Up.*healthy\|romm.*Up.*\(healthy\)"; do sleep 5; done' 2>/dev/null || true
msg_ok "RomM Started"

msg_info "Configuring Firewall"
if command -v ufw &>/dev/null; then
  $STD ufw allow 8080/tcp comment "RomM Web UI"
  $STD ufw --force enable
  msg_ok "Configured UFW Firewall"
else
  $STD apt-get install -y ufw
  $STD ufw allow 8080/tcp comment "RomM Web UI"
  $STD ufw allow 22/tcp comment "SSH"
  $STD ufw --force enable
  msg_ok "Installed and Configured UFW Firewall"
fi

motd_ssh
customize
cleanup_lxc
