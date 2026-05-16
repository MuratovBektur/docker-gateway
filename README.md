# Docker Gateway — Nginx + Certbot

Единая точка входа для двух приложений на одном IP-адресе.

```
Internet (80/443)
      │
   [nginx]  ← этот репозиторий
   /     \
app1    app2   ← ваши два репозитория
```

## Структура файлов

```
docker-gateway/
├── docker-compose.yml          # nginx + certbot
├── nginx/
│   ├── nginx.conf
│   └── conf.d/
│       ├── app1.conf           # домен → app1_service
│       └── app2.conf           # домен → app2_service
├── certbot/
│   ├── conf/                   # SSL-сертификаты (создаётся автоматически)
│   └── www/                    # ACME-webroot (создаётся автоматически)
├── init-ssl.sh                 # скрипт первоначального получения сертификатов
└── example-app-docker-compose.yml  # пример для ваших репозиториев
```

## Настройка

### Шаг 1. Отредактируйте домены в nginx/conf.d/

В `nginx/conf.d/app1.conf` замените:
- `app1.example.com` → ваш домен для первого приложения
- `app1_service` → имя сервиса из docker-compose репозитория 1

В `nginx/conf.d/app2.conf` — аналогично для второго приложения.

### Шаг 2. Подключите каждый репозиторий к общей сети

В `docker-compose.yml` каждого из двух репозиториев добавьте (см. `example-app-docker-compose.yml`):

```yaml
services:
  your_service:
    ...
    networks:
      - gateway_network
      - default

networks:
  gateway_network:
    external: true
  default:
    driver: bridge
```

### Шаг 3. Получите SSL-сертификаты (зависимые приложения не нужны)

> DNS-записи всех доменов должны уже указывать на ваш сервер.
> Приложения запускать не нужно — скрипт сам стартует nginx и получает сертификаты.

```bash
chmod +x init-ssl.sh

# Каждая группа в кавычках — один сертификат (первый домен = имя директории).
./init-ssl.sh your@email.com \
  "optom.store,www.optom.store,admin.optom.store" \
  "devoptom.fvds.ru"
```

Скрипт выполнит:
1. Создаст временные self-signed сертификаты (чтобы nginx мог стартовать)
2. Запустит gateway nginx
3. Получит реальные сертификаты от Let's Encrypt
4. Перезагрузит nginx

### Шаг 4. Запустите зависимые приложения

```bash
# В каждом из двух репозиториев (сеть gateway_network уже создана скриптом):
docker compose up -d
```

Убедиться что сеть существует:
```bash
docker network ls | grep gateway_network
```

## Обновление сертификатов

Certbot автоматически обновляет сертификаты каждые 12 часов (если до истечения осталось < 30 дней). Nginx перезагружает конфигурацию каждые 6 часов.

## Добавление нового приложения

1. Создайте `nginx/conf.d/app3.conf` по аналогии
2. Получите сертификат: `docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d app3.example.com`
3. Перезагрузите nginx: `docker compose exec nginx nginx -s reload`
