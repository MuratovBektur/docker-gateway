#!/bin/bash
# Первоначальное получение SSL-сертификатов.
#
# Использование:
#   ./init-ssl.sh EMAIL "primary.domain[,extra1,extra2]" ["next.domain[,...]" ...]
#
# Примеры:
#   ./init-ssl.sh me@mail.com "optom.store,www.optom.store,admin.optom.store" "devoptom.fvds.ru"
#
# Каждая группа доменов через запятую попадает в один сертификат.
# Первый домен группы — имя директории в /etc/letsencrypt/live/.

set -e

if [ "$#" -lt 2 ]; then
    echo "Использование: $0 EMAIL \"domain1[,d2,d3]\" [\"domain4[,d5]\" ...]"
    exit 1
fi

EMAIL="$1"
shift
CERT_GROUPS=("$@")

CERTBOT_CONF="./certbot/conf"
CERTBOT_WWW="./certbot/www"

mkdir -p "$CERTBOT_WWW"

# ─── Шаг 1: фиктивные сертификаты чтобы nginx мог стартовать ────────────────
echo "==> Создаём временные self-signed сертификаты..."
for GROUP in "${CERT_GROUPS[@]}"; do
    PRIMARY="${GROUP%%,*}"
    CERT_DIR="$CERTBOT_CONF/live/$PRIMARY"

    if [ -f "$CERT_DIR/fullchain.pem" ]; then
        echo "    $PRIMARY — сертификат уже существует, пропускаем"
        continue
    fi

    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout "$CERT_DIR/privkey.pem" \
        -out    "$CERT_DIR/fullchain.pem" \
        -subj   "/CN=$PRIMARY" 2>/dev/null
    echo "    $PRIMARY — временный сертификат создан"
done

# ─── Шаг 2: запускаем nginx ───────────────────────────────────────────────────
echo "==> Запускаем gateway nginx..."
docker compose up -d nginx
echo "    Ждём 3 секунды пока nginx поднимется..."
sleep 3

# ─── Шаг 3: получаем реальные сертификаты ────────────────────────────────────
echo "==> Получаем реальные сертификаты от Let's Encrypt..."
for GROUP in "${CERT_GROUPS[@]}"; do
    # Формируем аргументы -d domain1 -d domain2 ...
    IFS=',' read -ra DOMAINS <<< "$GROUP"
    D_ARGS=()
    for D in "${DOMAINS[@]}"; do
        D_ARGS+=(-d "$D")
    done
    PRIMARY="${DOMAINS[0]}"

    echo "    Получаем сертификат для: ${DOMAINS[*]}"
    docker compose run --rm certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        "${D_ARGS[@]}"
    echo "    $PRIMARY — сертификат получен"
done

# ─── Шаг 4: перезагружаем nginx с реальными сертификатами ────────────────────
echo "==> Перезагружаем nginx..."
docker compose exec nginx nginx -s reload

echo ""
echo "Готово! Сертификаты получены."
echo "Теперь запустите зависимые приложения: docker compose up -d"
