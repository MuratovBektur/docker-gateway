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

### Шаг 3. Получите SSL-сертификаты

> DNS-записи доменов должны уже указывать на ваш сервер.

```bash
chmod +x init-ssl.sh
./init-ssl.sh app1.example.com app2.example.com your@email.com
```

### Шаг 4. Запустите шлюз

```bash
docker compose up -d
```

### Шаг 5. Запустите свои приложения

```bash
# В каждом из двух репозиториев:
docker compose up -d
```

## Порядок запуска при первом деплое

1. Запустить `docker compose up -d nginx` (только nginx без SSL)
2. Запустить приложения: `docker compose up -d` в каждом репозитории
3. Запустить `./init-ssl.sh ...` для получения сертификатов
4. Перезапустить nginx: `docker compose restart nginx`

## Обновление сертификатов

Certbot автоматически обновляет сертификаты каждые 12 часов (если до истечения осталось < 30 дней). Nginx перезагружает конфигурацию каждые 6 часов.

## Добавление нового приложения

1. Создайте `nginx/conf.d/app3.conf` по аналогии
2. Получите сертификат: `docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d app3.example.com`
3. Перезагрузите nginx: `docker compose exec nginx nginx -s reload`
