#!/bin/bash
# Скрипт первоначального получения SSL-сертификатов.
# Запускать один раз перед первым стартом docker-compose.
# Использование: ./init-ssl.sh app1.example.com app2.example.com your@email.com

set -e

DOMAINS=("$@")
EMAIL="${DOMAINS[-1]}"
unset 'DOMAINS[-1]'

if [ ${#DOMAINS[@]} -lt 1 ]; then
    echo "Использование: $0 domain1.com domain2.com your@email.com"
    exit 1
fi

CERTBOT_WWW="./certbot/www"
CERTBOT_CONF="./certbot/conf"

mkdir -p "$CERTBOT_WWW" "$CERTBOT_CONF"

# Временно запускаем nginx только с HTTP для прохождения ACME-challenge
echo "Запускаем nginx для прохождения ACME-challenge..."
docker compose up -d nginx

for DOMAIN in "${DOMAINS[@]}"; do
    echo "Получаем сертификат для $DOMAIN..."
    docker compose run --rm certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN"
done

echo "Перезапускаем nginx с SSL..."
docker compose restart nginx

echo "Готово! Сертификаты получены для: ${DOMAINS[*]}"
