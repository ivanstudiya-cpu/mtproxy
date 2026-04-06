# 🔒 MTProxy Manager — Telegram MTProxy с Fake TLS

> Bash-скрипт для быстрого развёртывания и управления MTProxy серверами для Telegram с маскировкой трафика под HTTPS (Fake TLS). Работает через Docker, устанавливается за одну команду.

---

## ⚡ Быстрая установка

```bash
wget -O mtproxy.sh https://raw.githubusercontent.com/ivanstudiya-cpu/mtproxy/main/mtproxy.sh && chmod +x mtproxy.sh && sudo ./mtproxy.sh
```

После установки скрипт доступен глобально как команда `mtproxy`.

---

## 🎯 Возможности

### Ключевые функции
- **Fake TLS маскировка** — трафик выглядит как обычный HTTPS к реальному сайту (google.com, cloudflare.com и др.). Провайдер не определяет прокси.
- **Rotate Secret** — обновление секрета без пересоздания клиента. Старый конфиг автоматически бэкапится.
- **Auto-backup** — перед любым деструктивным действием (удаление, ротация) конфиг сохраняется в `/etc/mtproxy/backups/`.
- **Лог всех действий** — каждое действие записывается в `/var/log/mtproxy.log` с таймстампом.
- **QR-коды** — генерация сразу двух ссылок: `tg://` и `https://t.me/proxy` с QR прямо в терминале.
- **Статус и трафик** — просмотр CPU, памяти, сетевого трафика по каждому контейнеру.
- **Start / Stop / Restart** — интерактивное управление без ввода имён вручную.
- **Защита от случайного удаления** — полный снос требует ввода слова `DELETE`.

### Поддержка дистрибутивов
| Дистрибутив | Поддержка |
|---|---|
| Ubuntu 20.04+ | ✅ |
| Debian 10+ | ✅ |
| CentOS 7+ | ✅ |
| Fedora 36+ | ✅ |
| Rocky / AlmaLinux | ✅ |

---

## 📋 Меню управления

```
  1) Добавить новый прокси
  2) Список всех прокси
  3) Детали / QR по клиенту
  4) Статус и трафик
  5) Start / Stop / Restart
  6) Обновить секрет (rotate)
  7) Удалить прокси
  8) Просмотр лога
  9) Полное удаление
  0) Выход
```

---

## 🌐 Поддерживаемые домены для Fake TLS

64 предустановленных домена по категориям + возможность ввести любой свой.

**🌍 Международные (Tech)**
`google.com` `cloudflare.com` `microsoft.com` `apple.com` `amazon.com` `github.com` `stackoverflow.com` `gitlab.com`

**🌍 Международные (СМИ)**
`wikipedia.org` `bbc.com` `cnn.com` `reuters.com` `nytimes.com` `theguardian.com` `bloomberg.com` `forbes.com`

**🌍 Международные (Развлечения)**
`netflix.com` `twitch.tv` `discord.com` `zoom.us` `spotify.com` `reddit.com` `medium.com` `tumblr.com`

**🌍 Международные (Образование)**
`coursera.org` `udemy.com` `khanacademy.org` `edx.org` `duolingo.com` `ted.com` `skillshare.com`

**🇷🇺 Российские (СМИ)**
`lenta.ru` `rbc.ru` `ria.ru` `kommersant.ru` `vedomosti.ru` `iz.ru` `novayagazeta.ru` `meduza.io`

**🇷🇺 Российские (Tech/IT)**
`habr.com` `mail.ru` `yandex.ru` `vk.com` `2ch.hk` `pikabu.ru` `4pda.to` `3dnews.ru`

**🇷🇺 Российские (Образование)**
`stepik.org` `geekbrains.ru` `skillbox.ru` `hexlet.io` `netology.ru` `skillfactory.ru`

**🇷🇺 Российские (Сервисы)**
`gosuslugi.ru` `sberbank.ru` `tinkoff.ru` `avito.ru` `ozon.ru` `wildberries.ru` `kinopoisk.ru` `ivi.ru`

---

## 📁 Структура файлов

```
/usr/local/bin/mtproxy        — глобальная команда
/etc/mtproxy/proxies.conf     — конфиг всех прокси
/etc/mtproxy/backups/         — автобэкапы перед изменениями
/var/log/mtproxy.log          — лог всех действий
```

---

## 🔧 Как это работает

Скрипт использует Docker-образ [nineseconds/mtg:2](https://github.com/9seconds/mtg) — современную реализацию MTProxy с поддержкой Fake TLS (MTPROTO v2).

1. Генерируется секрет через `mtg generate-secret --hex <domain>` — он кодирует домен для Fake TLS.
2. Запускается Docker-контейнер с флагами `--restart unless-stopped` и ограничением логов (`--log-opt max-size=10m`).
3. Конфиг сохраняется локально для удобного управления.
4. Вам выдаётся готовая ссылка и QR-код для подключения.

---

## 🔗 Формат ссылки для подключения

```
tg://proxy?server=<IP>&port=<PORT>&secret=<SECRET>
https://t.me/proxy?server=<IP>&port=<PORT>&secret=<SECRET>
```

Ссылку можно открыть на телефоне или отсканировать QR прямо в терминале.

---

## 🛡 Требования

- Сервер с публичным IP (VPS/выделенный)
- Linux (Ubuntu / Debian / CentOS / Fedora)
- root-доступ (`sudo`)
- Открытый порт (443, 8443, 3128 или любой другой)
- Docker устанавливается автоматически, если не установлен

---

## 📝 Лицензия

MIT — используйте свободно.

---

> Скрипт предназначен для обхода блокировок Telegram в регионах с ограниченным доступом. Используйте ответственно и в соответствии с законодательством вашей страны.
