# Docker Gateway — Nginx + Certbot

Единая точка входа для нескольких приложений на одном IP-адресе.

```
Internet (80/443)
        │
     [nginx]  ← этот репозиторий
    /   |   \
app1  app2  admin  ← ваши репозитории / сервисы
```

## Текущие домены

| Домен | Куда |
|-------|------|
| `optom.store`, `www.optom.store` | `showroom_nginx_prod:80` |
| `admin.optom.store` | `host.docker.internal:3011` |
| `devoptom.fvds.ru` | `showroom_nginx_dev:80` |
| `mirjeans.kg`, `www.mirjeans.kg` | `mir-jeans_nginx_prod:80` |
| `marcel.kg`, `www.marcel.kg` | `marcel-clothes_nginx_prod:80` |

## Структура файлов

```
docker-gateway/
├── docker-compose.yml          # nginx + certbot
├── nginx/
│   ├── nginx.conf
│   └── conf.d/
│       ├── app1.conf           # optom.store → showroom_nginx_prod
│       ├── app2.conf           # devoptom.fvds.ru → showroom_nginx_dev
│       ├── admin.conf          # admin.optom.store → host.docker.internal:3011
│       ├── mirjeans.conf       # mirjeans.kg → mir-jeans_nginx_prod
│       └── marcel.conf         # marcel.kg → marcel-clothes_nginx_prod
├── certbot/
│   ├── conf/                   # SSL-сертификаты (в .gitignore)
│   └── www/                    # ACME-webroot (в .gitignore)
└── init-ssl.sh                 # скрипт первоначального получения сертификатов
```

## Настройка с нуля

### Шаг 1. Подключите каждый репозиторий к общей сети

В `docker-compose.yml` каждого приложения:

```yaml
services:
  nginx:                      # имя контейнера должно совпадать с proxy_pass в conf.d/
    expose:
      - "80"                  # НЕ ports: — только expose
    networks:
      - gateway_network
      - default

networks:
  gateway_network:
    external: true            # сеть создаётся шлюзом
  default:
    driver: bridge
```

> **Важно:** внутренний nginx приложения должен слушать только порт 80 без SSL и без
> HTTP→HTTPS редиректов. SSL терминируется на шлюзе.

### Шаг 2. Настройте nginx/conf.d/

В каждом `.conf` файле замените:
- домен (`optom.store`) → ваш домен
- имя upstream (`showroom_nginx_prod`) → `container_name` вашего nginx-контейнера

### Шаг 3. Получите SSL-сертификаты

> Требования перед запуском:
> - DNS всех доменов указывает на этот сервер
> - Порт 80 доступен снаружи

```bash
chmod +x init-ssl.sh
./init-ssl.sh your@email.com \
  "optom.store,www.optom.store,admin.optom.store" \
  "devoptom.fvds.ru"
```

Скрипт автоматически:
1. Останавливает системный nginx если он занимает порт 80
2. Открывает порты 80/443 в iptables
3. Временно переключает nginx в HTTP-only режим
4. Получает сертификаты от Let's Encrypt
5. Восстанавливает полный конфиг с SSL
6. Сохраняет правила iptables

Если домен упал по лимиту Let's Encrypt — скрипт не ломает остальные,
а выводит команду для повтора.

### Шаг 4. Запустите приложения

```bash
# Сеть gateway_network уже создана скриптом
cd ../showroom && docker compose up -d
cd ../showroom-dev && docker compose up -d
```

## Добавление нового домена

1. Создайте `nginx/conf.d/app3.conf` по аналогии с существующими
2. Запустите `init-ssl.sh` — он сам откроет порты, переключит nginx в HTTP-only и получит сертификат:
```bash
./init-ssl.sh your@email.com \
  "optom.store,www.optom.store,admin.optom.store" \
  "devoptom.fvds.ru" \
  "new.domain.com"
```
> Передайте все домены включая уже существующие — для них сертификаты будут пропущены
> (certbot не перевыпускает если до истечения больше 30 дней).

## Получить сертификат для домена вручную (без init-ssl.sh)

Используйте если:
- лимит Let's Encrypt ещё не сбросился и нужно добавить только один домен
- не хотите кратковременного даунтайма остальных сайтов
- шлюз уже работает, порты открыты

```bash
# nginx уже запущен и работает — просто запускаем certbot
docker run --rm \
  -v $(pwd)/certbot/conf:/etc/letsencrypt \
  -v $(pwd)/certbot/www:/var/www/certbot \
  --network gateway_network \
  certbot/certbot certonly \
  --webroot --webroot-path=/var/www/certbot \
  --email your@email.com --agree-tos --no-eff-email \
  -d new.domain.com

# Подключить конфиг и перезагрузить без рестарта
docker compose exec nginx nginx -s reload
```

Если лимит ещё не сбросился — узнать когда:
```bash
docker run --rm \
  -v $(pwd)/certbot/conf:/etc/letsencrypt \
  certbot/certbot certificates
```
Дату лимита также показывает [https://crt.sh/?q=fvds.ru](https://crt.sh/?q=fvds.ru) — поле `Not Before` у последних записей.

## Обновление сертификатов

Certbot автоматически обновляет сертификаты каждые 12 часов.
Nginx перезагружает конфиг каждые 6 часов.

## Известные особенности сервера

- **Системный nginx** — отключён (`systemctl disable nginx`), иначе занимает порт 80
- **ISPManager firewall** — блокирует порты 80/443; скрипт добавляет правила iptables автоматически
- **Let's Encrypt лимит** — `fvds.ru` — shared-домен, возможен лимит 50 сертификатов/неделю на весь домен
