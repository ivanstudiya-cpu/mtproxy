# 🔒 Messenger Proxy Manager

### Telegram MTProxy + Xray SOCKS5 + WireGuard VPN — всё в одном bash-скрипте

[![Version](https://img.shields.io/badge/version-4.9-blue?style=for-the-badge)](https://github.com/ivanstudiya-cpu/mtproxy/releases)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](https://github.com/ivanstudiya-cpu/mtproxy/blob/main/LICENSE)
[![Docker](https://img.shields.io/badge/docker-required-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docker.com)
[![Stars](https://img.shields.io/github/stars/ivanstudiya-cpu/mtproxy?style=for-the-badge&color=yellow)](https://github.com/ivanstudiya-cpu/mtproxy/stargazers)

**[🇷🇺 Русский](#-быстрая-установка) | [⭐ Поставить звезду](https://github.com/ivanstudiya-cpu/mtproxy)**

---

## 🚀 Зачем это нужно?

> Telegram заблокирован у провайдера? WhatsApp не работает? Этот скрипт поднимает прокси на твоём VPS за **60 секунд** и обходит любые блокировки.

```
✅ Telegram MTProxy  — встроен в Telegram, не нужен VPN
✅ Xray SOCKS5       — для WhatsApp, Instagram, браузера
✅ WireGuard VPN     — весь трафик через сервер, работает везде
✅ Fake TLS          — трафик выглядит как обычный HTTPS
✅ Docker            — изолированно, надёжно, легко удалить
✅ Один скрипт       — установка, управление, мониторинг
```

---

## ⚡ Быстрая установка

```bash
wget -O mtproxy.sh https://raw.githubusercontent.com/ivanstudiya-cpu/mtproxy/main/mtproxy.sh \
  && chmod +x mtproxy.sh \
  && sudo ./mtproxy.sh
```

> После установки скрипт доступен глобально — просто пиши `mtproxy` в терминале

**Требования:** VPS с Linux (Ubuntu 20.04+ / Debian 10+ / CentOS 7+) + root-доступ. Docker установится сам.

---

## 🖥️ Как выглядит

```
  ╔══════════════════════════════════════════════════════╗
  ║     Messenger Proxy Manager v4.9                    ║
  ║     Telegram MTProxy + Xray SOCKS5                  ║
  ╚══════════════════════════════════════════════════════╝

  ── Telegram MTProxy (Fake TLS) ──
  1)  Добавить новый MTProxy
  2)  Список всех прокси
  3)  Детали / QR по клиенту
  4)  Статус, трафик и подключения
  5)  Start / Stop / Restart
  6)  Обновить секрет (rotate)
  7)  Экспорт всех ссылок в файл
  8)  Миграция на новый сервер

  ── Xray SOCKS5 (WhatsApp / универсальный) ──
  9)  Меню Xray SOCKS5

  ── WireGuard VPN (WhatsApp / весь трафик) ──
  20) Меню WireGuard VPN

  ── Установить всё сразу ──
  10) Установить Telegram + Xray

  ── Telegram Бот ──
  19) Бот управления (add/delete/list/qr)

  ── Система ──
  11) Firewall    12) Healthcheck    13) Авто-rotate
  14) TG-уведомления    15) Обновить скрипт
  16) Просмотр лога     17) Удалить MTProxy
  18) Полное удаление
```

---

## 🎯 Возможности

### 🔵 Telegram MTProxy (Fake TLS)

| Фича | Описание |
|------|----------|
| **Fake TLS** | Трафик маскируется под HTTPS к реальному сайту |
| **64 домена** | Google, Cloudflare, VK, Habr, RBC и другие |
| **QR-коды** | `tg://` и `https://t.me/proxy` прямо в терминале |
| **Несколько клиентов** | Каждый на своём порту (443, 8443, 1080...) |
| **Rotate Secret** | Смена секрета без пересоздания прокси |
| **Авто-rotate** | Cron обновляет секреты раз в неделю/месяц |
| **Автобэкапы** | Перед каждым изменением |

### 🟣 Xray SOCKS5 (универсальный)

| Фича | Описание |
|------|----------|
| **Все приложения** | WhatsApp, Instagram, браузер, любые мессенджеры |
| **Порт по умолчанию** | 8443 — редко блокируется провайдерами |
| **Авторизация** | Открытый или с логином/паролем |
| **HTTP прокси** | Второй порт для приложений без SOCKS5 |
| **QR-код** | Для быстрого подключения |

### 🟢 WireGuard VPN (новое в v4.9)

| Фича | Описание |
|------|----------|
| **Весь трафик** | WhatsApp, любые приложения без настройки прокси в каждом |
| **Порт 53/UDP** | DNS-порт по умолчанию — не блокируется WiFi и операторами |
| **QR-код клиента** | Импорт на телефон за 5 секунд |
| **Несколько клиентов** | Отдельный конфиг для каждого устройства |
| **Фикс Docker NAT** | Явные iptables правила — работает вместе с Docker |
| **Управление из меню** | Добавить/удалить клиента, показать QR |

### ⚙️ Система

| Фича | Описание |
|------|----------|
| **Healthcheck** | Cron каждые 5 минут — упавший прокси перезапускается сам |
| **TG уведомления** | Бот пишет когда прокси упал и восстановился |
| **Telegram бот** | Управление прокси прямо из Telegram (/add /delete /list /qr) |
| **Firewall-помощник** | Автооткрытие портов в UFW/firewalld/iptables |
| **Экспорт** | Все ссылки в один файл одной командой |
| **Миграция** | Перенос на новый сервер одной командой |
| **Авто-обновление** | Скрипт обновляется с GitHub |

---

## 📱 Подключение на телефоне

### Telegram (30 секунд)

```
1. Скрипт выдаёт ссылку: tg://proxy?server=IP&port=443&secret=...
2. Открой ссылку на телефоне
3. Telegram спросит "Подключиться к прокси?"
4. Нажми "Подключить" ✅
```

Или отсканируй QR-код прямо из терминала.

### WhatsApp / все приложения — WireGuard (рекомендуется)

1. Установи приложение **WireGuard** из Play Store / App Store
2. В скрипте выбери `20) → 1)` (установить WireGuard)
3. Добавь клиента `20) → 2)` — появится QR-код
4. В приложении WireGuard нажми `+` → `Сканировать QR`
5. Включи VPN — весь трафик идёт через сервер ✅

> **Совет:** WireGuard работает на порту 53/UDP по умолчанию — он не блокируется ни домашними роутерами, ни мобильными операторами.

### WhatsApp через Xray SOCKS5 (альтернатива)

```
Настройки WhatsApp → Хранилище и данные → Прокси
Хост: IP_сервера
Порт: 8443
```

---

## 🛡 Безопасность (v4.6+)

- Логи и конфиги создаются с правами `600` — читает только root
- Секреты MTProxy **не пишутся** в лог-файл
- Конфиги бота и уведомлений читаются через `grep`, а не через `source` — исключено выполнение произвольного кода
- Пароли Xray хранятся в base64 — символ `|` в пароле не ломает парсинг
- Ввод номера контейнера валидируется — отрицательные индексы заблокированы
- `python3` проверяется при установке
- Exponential backoff в Telegram боте при сетевых ошибках

---

## 🌐 Домены для Fake TLS

<details>
<summary>🌍 Международные (32 домена)</summary>

**Tech:** `google.com` `cloudflare.com` `microsoft.com` `apple.com` `amazon.com` `github.com` `stackoverflow.com` `gitlab.com`

**СМИ:** `wikipedia.org` `bbc.com` `cnn.com` `reuters.com` `nytimes.com` `theguardian.com` `bloomberg.com` `forbes.com`

**Развлечения:** `netflix.com` `twitch.tv` `discord.com` `zoom.us` `spotify.com` `reddit.com` `medium.com` `tumblr.com`

**Образование:** `coursera.org` `udemy.com` `khanacademy.org` `edx.org` `duolingo.com` `ted.com` `skillshare.com`
</details>

<details>
<summary>🇷🇺 Российские (29 доменов)</summary>

**СМИ:** `lenta.ru` `rbc.ru` `ria.ru` `kommersant.ru` `vedomosti.ru` `iz.ru` `novayagazeta.ru` `meduza.io`

**Tech/IT:** `habr.com` `mail.ru` `yandex.ru` `vk.com` `2ch.hk` `pikabu.ru` `4pda.to` `3dnews.ru`

**Образование:** `stepik.org` `geekbrains.ru` `skillbox.ru` `hexlet.io` `netology.ru` `skillfactory.ru`

**Сервисы:** `gosuslugi.ru` `sberbank.ru` `tinkoff.ru` `avito.ru` `ozon.ru` `wildberries.ru` `kinopoisk.ru` `ivi.ru`
</details>

---

## 🛠 Требования

| | |
|---|---|
| **ОС** | Ubuntu 20.04+, Debian 10+, CentOS 7+, Fedora 36+, Rocky/AlmaLinux |
| **RAM** | от 512MB (1GB+ рекомендуется) |
| **Docker** | Устанавливается автоматически |
| **Права** | root / sudo |
| **Порты** | 443 (MTProxy), 8443 (Xray SOCKS5), 53/UDP (WireGuard) |

---

## 📋 Changelog

<details>
<summary>История версий</summary>

### v4.9 — WireGuard VPN
- Добавлен WireGuard VPN — весь трафик устройства через сервер
- Порт 53/UDP по умолчанию — обходит блокировки WiFi и операторов
- QR-код для импорта клиента одним сканированием
- Фикс конфликта NAT с Docker (явные iptables правила для 10.8.0.0/24)
- Управление клиентами из меню (добавить/удалить/показать QR)

### v4.7 — Xray порт
- Порт Xray по умолчанию изменён с 1080 на 8443
- Меню выбора порта при установке Xray

### v4.6 — Безопасность
- `source notify.conf` и `source bot.conf` заменены на безопасный `grep+cut`
- Секрет MTProxy убран из логов авто-rotate
- `chmod 600` на лог-файл при создании
- Валидация IDX во всех меню (отрицательные индексы заблокированы)
- Пароли Xray хранятся в base64 — символ `|` в пароле не ломает конфиг
- Exponential backoff в Telegram боте при сетевых ошибках
- Проверка наличия `python3` при установке
- Безопасная установка скрипта при запуске через `curl | bash`

### v4.5 — Telegram бот
- Бот управления прокси из Telegram (/add /delete /list /status /qr /restart)
- Admin-only фильтр, авторизация по chat_id

### v4.0 — Xray SOCKS5
- Добавлен Xray SOCKS5 (WhatsApp / универсальный прокси)
- Пункт "Установить всё сразу" (Telegram + Xray)
- Авторизация Xray (открытый / логин+пароль)
- QR-код для SOCKS5

### v3.0 — Полная автоматизация
- Таблица статусов портов с firewall статусом
- TG уведомления, healthcheck, авто-rotate по cron
- Экспорт ссылок, миграция на новый сервер
- Авто-обновление скрипта с GitHub

### v2.0 — Управление
- Rotate Secret с автобэкапом
- Логи, QR-коды tg:// и https://
- 64 домена по категориям

### v1.0 — Старт
- Базовый MTProxy с Fake TLS через Docker
</details>

---

## 🤝 Помочь проекту

Если скрипт помог — поставь ⭐ на GitHub! Это помогает другим найти проект.

Нашёл баг или есть идея? Открывай [Issue](https://github.com/ivanstudiya-cpu/mtproxy/issues) — разберёмся!

---

**Сделано с ❤️ для русскоязычного сообщества**

[⭐ Поставить звезду](https://github.com/ivanstudiya-cpu/mtproxy) · [🐛 Сообщить о баге](https://github.com/ivanstudiya-cpu/mtproxy/issues) · [💡 Предложить фичу](https://github.com/ivanstudiya-cpu/mtproxy/issues)
