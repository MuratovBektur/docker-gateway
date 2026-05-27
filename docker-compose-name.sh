#!/bin/bash
# Определяет доступную команду docker compose / docker-compose
# Использование: source docker-compose-name.sh
# После: "${DOCKER_COMPOSE[@]}" up -d

if docker compose version &>/dev/null 2>&1; then
    DOCKER_COMPOSE=("docker" "compose")
elif docker-compose version &>/dev/null 2>&1; then
    DOCKER_COMPOSE=("docker-compose")
else
    echo "❌ docker compose не найден"
    exit 1
fi
