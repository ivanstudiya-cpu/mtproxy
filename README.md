<div align="center">

# 🔒 Messenger Proxy Manager

### Telegram MTProxy · Xray SOCKS5 · VLESS+Reality · Cloudflare WARP
### Всё в одном bash-скрипте. Работает за 1 минуту.

[![Version](https://img.shields.io/badge/version-5.1-blue?style=for-the-badge)](https://github.com/ivan-yurich/mtproxy/releases)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-required-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docker.com)
[![Stars](https://img.shields.io/github/stars/ivan-yurich/mtproxy?style=for-the-badge&color=yellow)](https://github.com/ivan-yurich/mtproxy/stargazers)
[![Security](https://img.shields.io/badge/security-hardened-brightgreen?style=for-the-badge)](#-безопасность)

**[🇷🇺 Русский](#-быстрая-установка) · [🇬🇧 English](#-quick-install) · [⭐ Star on GitHub](https://github.com/ivan-yurich/mtproxy)**

</div>

---

## 🇷🇺 Русский

### Зачем это нужно?

> Telegram заблокирован? WhatsApp не работает? Нужен надёжный VPN без лишних настроек? Этот скрипт поднимает три типа прокси на твоём VPS за **60 секунд** и обходит любые блокировки.

```
✅ Telegram MTProxy  — встроен в Telegram, не нужен VPN, Fake TLS маскировка
✅ Xray SOCKS5       — для WhatsApp, Instagram, браузера (HTTP + SOCKS5)
✅ VLESS + Reality   — обходит DPI, маскируется под обычный HTTPS
✅ Cloudflare WARP   — отдельный SOCKS5/HTTP прокси с outbound через WARP
✅ Telegram-бот      — управление прокси прямо из Telegram
✅ Один скрипт       — установка, управление, мониторинг, автообновление
```

### ⚡ Быстрая установка

```bash
wget -O mtproxy.sh https://raw.githubusercontent.com/ivan-yurich/mtproxy/main/mtproxy.sh \
  && chmod +x mtproxy.sh \
  && sudo ./mtproxy.sh
```

После установки: просто пиши `mtproxy` в терминале.

**Требования:** VPS с Linux (Ubuntu/Debian/CentOS) + root. Docker установится сам.

---

### 🖥️ Меню

```
  ── Telegram MTProxy (Fake TLS) ──
  1)  Добавить новый MTProxy
  2)  Список всех прокси
  3)  Детали / QR по клиенту
  4)  Статус, трафик и подключения
  5)  Start / Stop / Restart
  6)  Обновить секрет (rotate)
  7)  Экспорт всех ссылок в файл
  8)  Миграция на новый сервер

  ── VLESS + XTLS-Reality (Anti-DPI) ──
  9)  Меню VLESS+Reality

  ── Xray SOCKS5 (WhatsApp / универсальный) ──
  10) Меню Xray SOCKS5
  21) Меню Cloudflare WARP
  11) Установить Telegram + Xray

  ── Система ──
  12) Firewall      13) Healthcheck    14) Авто-rotate
  15) TG уведомления  16) Обновить скрипт
  20) Telegram-бот управления
```

---

### 🎯 Три типа прокси

#### 🔵 Telegram MTProxy (Fake TLS)
Встроенный прокси Telegram — работает прямо в приложении. Трафик маскируется под HTTPS к реальному сайту (64 домена: Google, Cloudflare, VK, Habr, RBC...).

#### 🟣 Xray SOCKS5 + HTTP
Для **всех приложений** — WhatsApp, Instagram, браузер:
- SOCKS5 порт (1080) — браузер, система
- HTTP порт (1081) — WhatsApp, Instagram, Android WiFi

#### 🔴 VLESS + XTLS-Reality
Самый устойчивый к блокировкам протокол. Маскируется под TLS-запрос к белому сайту (microsoft.com, apple.com...). Не нужен домен или сертификат. Работает там, где SOCKS5 блокируется глубокой инспекцией пакетов (DPI).

Приложения: **v2rayNG** / **Nekobox** (Android), **Streisand** / **Shadowrocket** (iPhone), **Hiddify** (Windows).

#### 🟢 Cloudflare WARP proxy
Отдельный `xray-warp` контейнер: входящие SOCKS5/HTTP подключения идут через Xray WireGuard outbound в Cloudflare WARP. Режим не меняет маршруты всего VPS и не трогает SSH, поэтому его безопаснее использовать на рабочем сервере.

- публичный режим с обязательным логином и паролем
- localhost-only режим для локальных проверок на сервере
- автоматическая генерация WARP-профиля через `wgcf`
- проверка через Cloudflare trace (`warp=on` / `warp=plus`)

---

### 🤖 Telegram-бот управления

Управляй прокси прямо из Telegram:

| Команда | Действие |
|---|---|
| `/add ivan 443 cloudflare.com` | Создать прокси + QR-код |
| `/delete ivan` | Удалить прокси |
| `/list` | Все прокси со ссылками |
| `/status` | Статус контейнеров |
| `/qr ivan` | QR-код для клиента |
| `/restart ivan` | Перезапустить прокси |

Бот отвечает только тебе (по chat_id). Запускается как systemd-служба — работает после ребута.

---

### 🔒 Безопасность

В этой версии проделана большая работа по безопасности и отказоустойчивости:

- `umask 077`, `chmod 600/700` и отдельные helper-функции для файлов с токенами, секретами, WARP-профилями и migration/export файлами
- строгая валидация портов, индексов меню и доменов перед Docker/firewall операциями
- централизованный ввод пользователя с лимитами длины для пунктов меню, токенов, ID, паролей и WARP-ключей
- Xray SOCKS5 больше не создаёт публичный open proxy по умолчанию: пароль включён сразу, открытый режим требует явного подтверждения `OPEN`
- JSON-конфиги с логинами и паролями больше не выводятся в терминал при ошибке проверки
- firewall helper не добавляет дублирующиеся iptables-правила и отказывается работать с некорректными портами
- `--bot-daemon` и systemd-режим Telegram-бота исправлены, чтобы бот не запускался вторым polling-процессом
- self-update проверяет скачанный скрипт через `bash -n` перед заменой `/usr/local/bin/mtproxy`
- rotate секрета не удаляет рабочий контейнер, если новый секрет не сгенерировался, и пробует восстановить старый контейнер при неудачном старте
- WARP реализован как отдельный Xray-контейнер, не меняющий системные маршруты VPS

---

### 📱 Подключение на телефоне

**Telegram** — открой ссылку `tg://proxy?...` или отсканируй QR прямо из терминала.

**WhatsApp** → Настройки → Хранилище и данные → Прокси:
```
Хост: IP_сервера   Порт: 1081   Тип: HTTP
```

**VLESS/Reality** — импортируй ссылку `vless://...` в v2rayNG или Nekobox.

---

### 🌐 Домены для Fake TLS (64 домена)

<details>
<summary>🌍 Международные (32 домена)</summary>

`google.com` `cloudflare.com` `microsoft.com` `apple.com` `amazon.com` `github.com` `stackoverflow.com` `gitlab.com` `wikipedia.org` `bbc.com` `cnn.com` `reuters.com` `nytimes.com` `theguardian.com` `bloomberg.com` `forbes.com` `netflix.com` `twitch.tv` `discord.com` `zoom.us` `spotify.com` `reddit.com` `medium.com` `tumblr.com` `coursera.org` `udemy.com` `khanacademy.org` `edx.org` `duolingo.com` `ted.com` `skillshare.com`

</details>

<details>
<summary>🇷🇺 Российские (29 доменов)</summary>

`lenta.ru` `rbc.ru` `ria.ru` `kommersant.ru` `vedomosti.ru` `iz.ru` `novayagazeta.ru` `meduza.io` `habr.com` `mail.ru` `yandex.ru` `vk.com` `2ch.hk` `pikabu.ru` `4pda.to` `3dnews.ru` `stepik.org` `geekbrains.ru` `skillbox.ru` `hexlet.io` `netology.ru` `skillfactory.ru` `gosuslugi.ru` `sberbank.ru` `tinkoff.ru` `avito.ru` `ozon.ru` `wildberries.ru` `kinopoisk.ru` `ivi.ru`

</details>

---

### 📋 Changelog

<details>
<summary>История версий</summary>

#### v5.1 — Security hardening + Cloudflare WARP
- Большой аудит безопасности bash-скрипта
- Добавлен Cloudflare WARP proxy через Xray WireGuard outbound
- Исправлен entrypoint: Reality и WARP функции объявляются до запуска меню
- Исправлен `mtproxy --bot-daemon` для systemd Telegram-бота
- Xray SOCKS5 больше не поднимает open proxy по умолчанию
- Усилены права доступа к конфигам, экспортам, миграциям и WARP-профилям
- Добавлены проверки портов, доменов и индексов меню
- Централизован ввод пользователя и добавлены лимиты длины для чувствительных значений
- JSON-конфиги с секретами больше не печатаются при ошибке проверки
- Self-update проверяет синтаксис скачанного файла
- Rotate секрета стал безопаснее при ошибках генерации или старта контейнера

#### v5.0 — VLESS+Reality + Security hardening
- Добавлен VLESS + XTLS-Reality (Anti-DPI, не нужен домен)
- `mktemp` для временных файлов — защита от symlink-атак
- Systemd unit для Telegram-бота (работает после ребута)
- Logrotate для `/var/log/mtproxy.log`
- Защита от пустых переменных в `xray_delete`
- Логирование ошибок парсинга в боте

#### v4.5 — WhatsApp fix
- HTTP прокси (порт+1) для WhatsApp — `allowTransparent: true`
- Явный `listen: 0.0.0.0` и DNS в конфиге Xray
- `domainStrategy: UseIP` для лучшего DNS

#### v4.4 — Security audit
- Статические проверки bash-синтаксиса
- Санитизация CLIENT_ID везде
- Исправлен `xray_delete` — читает порты до удаления конфига
- Проверка HTTP порта на конфликт с MTProxy

#### v4.0 — Xray SOCKS5
- Xray SOCKS5 для WhatsApp и всех приложений
- Telegram-бот управления (/add, /delete, /list, /qr...)
- Установить всё сразу (Telegram + Xray)

#### v3.0 — Автоматизация
- Healthcheck, авто-rotate секретов, TG уведомления
- Экспорт ссылок, миграция на новый сервер
- Таблица статусов портов с firewall

#### v2.0 — Управление
- Rotate Secret, автобэкапы, логи
- 64 домена по категориям

</details>

---

## 🇬🇧 English

### What is this?

> A single bash script that deploys multiple proxy modes on your VPS in **60 seconds** to bypass censorship.

```
✅ Telegram MTProxy  — built-in Telegram proxy, Fake TLS masking
✅ Xray SOCKS5+HTTP  — for WhatsApp, Instagram, browsers
✅ VLESS + Reality   — anti-DPI, mimics real HTTPS traffic
✅ Cloudflare WARP   — separate SOCKS5/HTTP proxy routed through WARP
✅ Telegram Bot      — manage proxies directly from Telegram
✅ One script        — install, manage, monitor, auto-update
```

### ⚡ Quick Install

```bash
wget -O mtproxy.sh https://raw.githubusercontent.com/ivan-yurich/mtproxy/main/mtproxy.sh \
  && chmod +x mtproxy.sh \
  && sudo ./mtproxy.sh
```

After install: just type `mtproxy` in terminal.

**Requirements:** VPS with Linux (Ubuntu/Debian/CentOS) + root. Docker installs automatically.

---

### 🎯 Three Proxy Types

#### 🔵 Telegram MTProxy (Fake TLS)
Native Telegram proxy — works inside the app, no VPN needed. Traffic is disguised as HTTPS to a real website (64 domains: Google, Cloudflare, VK, Habr...).

#### 🟣 Xray SOCKS5 + HTTP
For **any app** — WhatsApp, Instagram, browsers:
- SOCKS5 port (1080) — browser, system-wide
- HTTP port (1081) — WhatsApp, Instagram, Android WiFi proxy

#### 🔴 VLESS + XTLS-Reality
The most censorship-resistant protocol. Mimics a TLS handshake to a real site (microsoft.com, apple.com...). No domain or certificate required. Works against Deep Packet Inspection (DPI).

Apps: **v2rayNG** / **Nekobox** (Android), **Streisand** / **Shadowrocket** (iPhone), **Hiddify** (Windows/Mac).

---

### 🤖 Telegram Bot

Manage proxies directly from Telegram chat:

| Command | Action |
|---|---|
| `/add user 443 cloudflare.com` | Create proxy + QR code |
| `/delete user` | Delete proxy |
| `/list` | All proxies with links |
| `/status` | Container status |
| `/qr user` | QR code for client |
| `/restart user` | Restart proxy |

Bot only responds to you (by chat_id). Runs as a systemd service — survives reboots.

---

### 📱 Client Setup

**Telegram** — open the `tg://proxy?...` link or scan the QR code from terminal.

**WhatsApp** → Settings → Storage and Data → Proxy:
```
Host: your_server_ip   Port: 1081   Type: HTTP
```

**VLESS/Reality** — import `vless://...` link into v2rayNG or Nekobox.

---

### 🔒 Security Features

- Major security hardening pass across the bash script
- `umask 077`, `chmod 600/700`, and helpers for secret configs, exports, migrations, and WARP profiles
- Strict validation for ports, menu indexes, and domains before Docker/firewall operations
- Centralized bounded input helpers for menu choices, tokens, IDs, passwords, and WARP keys
- Xray SOCKS5 no longer creates a public open proxy by default
- Sensitive Xray JSON configs are not printed to the terminal when validation fails
- Telegram bot daemon mode is fixed for systemd and avoids duplicate polling processes
- Self-update validates downloaded scripts with `bash -n` before replacing `/usr/local/bin/mtproxy`
- Secret rotation is safer when generation or container startup fails
- WARP runs in a separate Xray container without changing VPS system routes

---

### 🛡 Requirements

| | |
|---|---|
| **OS** | Ubuntu 20.04+, Debian 10+, CentOS 7+, Fedora 36+, Rocky/AlmaLinux |
| **RAM** | 512MB+ (1GB+ recommended) |
| **Docker** | Installed automatically |
| **Access** | root / sudo |
| **Ports** | 443, 8443, 1080, 1081 or custom |

---

## 🤝 Contributing

Found a bug or have an idea? Open an [Issue](https://github.com/ivan-yurich/mtproxy/issues)!

If this script helped you — please ⭐ the repo. It helps others find the project.

---

<div align="center">

**Сделано с ❤️ для русскоязычного сообщества · Made with ❤️ for the community**

[⭐ Star](https://github.com/ivan-yurich/mtproxy) · [🐛 Bug Report](https://github.com/ivan-yurich/mtproxy/issues) · [💡 Feature Request](https://github.com/ivan-yurich/mtproxy/issues)

</div>
