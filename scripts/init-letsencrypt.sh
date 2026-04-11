#!/bin/bash
#
# First-time Let's Encrypt certificate issuance.
#
# Solves the chicken-and-egg problem: nginx needs certs to start with SSL,
# but certbot needs nginx serving HTTP to complete the ACME challenge.
#
# Run once on the VPS before starting the full prod stack:
#   sudo bash scripts/init-letsencrypt.sh
#
# After this script completes, use the normal prod compose command:
#   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

set -euo pipefail

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

if [ -z "${DOMAIN:-}" ] || [ -z "${CERTBOT_EMAIL:-}" ]; then
    echo "Error: DOMAIN and CERTBOT_EMAIL must be set in .env"
    exit 1
fi

COMPOSE="docker compose -f docker-compose.yml -f docker-compose.prod.yml"

echo "==> Requesting Let's Encrypt certificate for ${DOMAIN}"

# Step 1: Create dummy certificate so nginx can start with the SSL block
echo "==> Creating dummy certificate..."
$COMPOSE run --rm --no-deps --entrypoint "" certbot \
    sh -c "mkdir -p /etc/letsencrypt/live/${DOMAIN} && \
           openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
           -keyout /etc/letsencrypt/live/${DOMAIN}/privkey.pem \
           -out /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
           -subj '/CN=${DOMAIN}' 2>/dev/null"

# Step 2: Start nginx (boots successfully with the dummy cert)
echo "==> Starting nginx with dummy certificate..."
$COMPOSE up -d nginx

echo "==> Waiting for nginx to be ready..."
sleep 5

# Step 3: Remove the dummy certificate
echo "==> Removing dummy certificate..."
$COMPOSE run --rm --no-deps --entrypoint "" certbot \
    sh -c "rm -rf /etc/letsencrypt/live/${DOMAIN}"

# Step 4: Request real certificate from Let's Encrypt
echo "==> Requesting real certificate from Let's Encrypt..."
$COMPOSE run --rm --entrypoint "" certbot \
    certbot certonly --webroot -w /var/www/certbot \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos --no-eff-email \
    --force-renewal \
    -d "${DOMAIN}"

# Step 5: Reload nginx to pick up the real certificate
echo "==> Reloading nginx with real certificate..."
$COMPOSE exec nginx nginx -s reload

echo ""
echo "==> Done! Certificate issued for ${DOMAIN}"
echo ""
echo "    To start the full stack:"
echo "    ${COMPOSE} up -d"
