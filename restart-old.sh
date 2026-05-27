#!/bin/bash
# Скрипт перезапуска приложения с логами.
# Положить в корень репозитория приложения (showroom, mir-jeans и т.д.)

set -e

# ─── Цвета ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
ok()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✔ $1${NC}"; }
warn(){ echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $1${NC}"; }
err() { echo -e "${RED}[$(date '+%H:%M:%S')] ✘ $1${NC}"; exit 1; }

# ─── Шаг 1: git pull ─────────────────────────────────────────────────────────
log "Получаем последние изменения..."
git pull || err "git pull завершился с ошибкой"
ok "git pull"

# ─── Шаг 2: сборка клиента (если есть build.sh) ──────────────────────────────
if [ -f "./client/build.sh" ]; then
    log "Собираем клиент..."
    cd client
    source ./build.sh
    cd ..
    ok "Клиент собран"
else
    warn "client/build.sh не найден — пропускаем сборку"
fi

# ─── Шаг 3: определяем команду docker compose ────────────────────────────────
source "$(dirname "$0")/docker-compose-name.sh"
ok "Docker compose: ${DOCKER_COMPOSE[*]}"

# ─── Шаг 4: пересборка и запуск ──────────────────────────────────────────────
log "Останавливаем контейнеры..."
"${DOCKER_COMPOSE[@]}" down

log "Собираем и запускаем..."
"${DOCKER_COMPOSE[@]}" up -d --build
ok "Контейнеры запущены"

# ─── Шаг 5: логи ─────────────────────────────────────────────────────────────
log "Логи (Ctrl+C для выхода):"
"${DOCKER_COMPOSE[@]}" logs -f --tail=100
