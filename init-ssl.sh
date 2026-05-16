#!/bin/bash
# Первоначальное получение SSL-сертификатов.
#
# Использование:
#   ./init-ssl.sh EMAIL "primary.domain[,extra1,extra2]" ["next.domain[,...]" ...]
#
# Пример:
#   ./init-ssl.sh me@mail.com "optom.store,www.optom.store,admin.optom.store" "devoptom.fvds.ru"

set -e

if [ "$#" -lt 2 ]; then
    echo "Использование: $0 EMAIL \"domain1[,d2,d3]\" [\"domain4\" ...]"
    exit 1
fi

EMAIL="$1"
shift
CERT_GROUPS=("$@")

mkdir -p "./certbot/www"

# ─── Вспомогательные функции ──────────────────────────────────────────────────

_restore_nginx_config() {
    if [ -d "./nginx/conf.d.bak" ]; then
        rm -f ./nginx/conf.d/acme-only.conf
        mv ./nginx/conf.d.bak/*.conf ./nginx/conf.d/ 2>/dev/null || true
        rmdir ./nginx/conf.d.bak 2>/dev/null || true
    fi
}

cleanup() {
    echo ""
    echo "==> Восстанавливаем конфиг nginx после прерывания..."
    _restore_nginx_config
    docker compose restart nginx 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ─── Шаг 1: остановить системный nginx если запущен ──────────────────────────
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo "==> Останавливаем системный nginx (занимает порт 80)..."
    systemctl stop nginx
    systemctl disable nginx
fi

# ─── Шаг 2: открыть порты 80 и 443 в iptables ────────────────────────────────
echo "==> Открываем порты 80 и 443..."
if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
fi
if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
fi

# ─── Шаг 3: переключить nginx в HTTP-only режим ───────────────────────────────
echo "==> Переключаем nginx в HTTP-only режим..."
mkdir -p ./nginx/conf.d.bak
mv ./nginx/conf.d/*.conf ./nginx/conf.d.bak/ 2>/dev/null || true

cat > ./nginx/conf.d/acme-only.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 200 "obtaining certs...";
        add_header Content-Type text/plain;
    }
}
EOF

# ─── Шаг 4: запустить / перезапустить nginx ───────────────────────────────────
echo "==> Запускаем nginx (HTTP-only)..."
docker compose up -d nginx
docker compose restart nginx
sleep 4

# Проверяем что nginx реально отвечает
if ! curl -sf http://localhost/ > /dev/null; then
    echo "ОШИБКА: nginx не отвечает на localhost:80"
    echo "Логи:"
    docker compose logs nginx --tail=20
    exit 1
fi
echo "    nginx отвечает на порту 80"

# ─── Шаг 5: получить сертификаты ─────────────────────────────────────────────
echo "==> Получаем сертификаты от Let's Encrypt..."
FAILED_GROUPS=()

for GROUP in "${CERT_GROUPS[@]}"; do
    IFS=',' read -ra DOMAINS <<< "$GROUP"
    D_ARGS=()
    for D in "${DOMAINS[@]}"; do D_ARGS+=(-d "$D"); done
    PRIMARY="${DOMAINS[0]}"

    echo "    Получаем сертификат для: ${DOMAINS[*]}"
    if docker run --rm \
        -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
        -v "$(pwd)/certbot/www:/var/www/certbot" \
        --network gateway_network \
        certbot/certbot certonly \
        --webroot --webroot-path=/var/www/certbot \
        --email "$EMAIL" --agree-tos --no-eff-email \
        "${D_ARGS[@]}"; then
        echo "    $PRIMARY — OK"
    else
        echo "    $PRIMARY — ОШИБКА (пропускаем, можно получить позже)"
        FAILED_GROUPS+=("$GROUP")
    fi
done

# ─── Шаг 6: восстановить конфиги и перезапустить nginx с SSL ─────────────────
echo "==> Восстанавливаем полный конфиг nginx..."
trap - EXIT INT TERM
_restore_nginx_config

echo "==> Перезапускаем nginx с SSL..."
docker compose restart nginx
sleep 4

# ─── Шаг 7: сохранить правила iptables ───────────────────────────────────────
if command -v iptables-save > /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo "==> Правила iptables сохранены"
fi

# ─── Итог ─────────────────────────────────────────────────────────────────────
echo ""
if [ ${#FAILED_GROUPS[@]} -eq 0 ]; then
    echo "Готово! Все сертификаты получены."
else
    echo "Готово, но следующие домены не получили сертификат (лимит или DNS):"
    for G in "${FAILED_GROUPS[@]}"; do
        echo "  - $G"
    done
    echo ""
    echo "Повторите для проблемных доменов:"
    for G in "${FAILED_GROUPS[@]}"; do
        IFS=',' read -ra DD <<< "$G"
        DARGS=""
        for D in "${DD[@]}"; do DARGS="$DARGS -d $D"; done
        echo "  docker run --rm \\"
        echo "    -v \$(pwd)/certbot/conf:/etc/letsencrypt \\"
        echo "    -v \$(pwd)/certbot/www:/var/www/certbot \\"
        echo "    --network gateway_network \\"
        echo "    certbot/certbot certonly --webroot --webroot-path=/var/www/certbot \\"
        echo "    --email $EMAIL --agree-tos --no-eff-email $DARGS"
    done
fi
echo ""
echo "Запустите зависимые приложения:"
echo "  cd ../showroom && docker compose up -d"
