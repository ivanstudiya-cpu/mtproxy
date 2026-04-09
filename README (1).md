<div align="center">

# 🔒 Messenger Proxy Manager

### Telegram MTProxy с Fake TLS + Xray SOCKS5 для WhatsApp
### Всё в одном bash-скрипте. Работает за 1 минуту.

[![Version](https://img.shields.io/badge/version-4.0-blue?style=for-the-badge)](https://github.com/ivanstudiya-cpu/mtproxy/releases)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-required-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docker.com)
[![Stars](https://img.shields.io/github/stars/ivanstudiya-cpu/mtproxy?style=for-the-badge&color=yellow)](https://github.com/ivanstudiya-cpu/mtproxy/stargazers)

**[🇷🇺 Русский](#-быстрая-установка) | [📖 Документация](#-возможности) | [⭐ Поставить звезду](https://github.com/ivanstudiya-cpu/mtproxy)**

</div>

---

## 🚀 Зачем это нужно?

> Telegram заблокирован у провайдера? WhatsApp не работает? Этот скрипт поднимает прокси на твоём VPS за **60 секунд** и обходит любые блокировки.

```
✅ Telegram MTProxy  — встроен в Telegram, не нужен VPN
✅ Xray SOCKS5       — для WhatsApp, Instagram, браузера
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

> После установки скрипт доступен глобально: просто пиши `mtproxy` в терминале

**Требования:** VPS с Linux (Ubuntu/Debian/CentOS) + root-доступ. Docker установится сам.

---

## 🖥️ Как выглядит

```
  ╔══════════════════════════════════════════════════════╗
  ║     Messenger Proxy Manager v4.0                    ║
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

  ── Установить всё сразу ──
  10) Установить Telegram + Xray

  ── Система ──
  11) Firewall    12) Healthcheck    13) Авто-rotate
  14) TG-уведомления    15) Обновить скрипт
```

```
  Статус портов:
  ──────────────────────────────────────
  Порт    Процесс       Firewall          Прокси
  ──────────────────────────────────────
  443     занят         открыт            ivan
  8443    свободен      закрыт
  3128    свободен      открыт
  1080    занят         открыт            dows
  ──────────────────────────────────────

  Выберите порт:
  1) 443   (рекомендуется — HTTPS)
  2) 8443
  3) 3128
  4) 1080  (SOCKS)
  5) Свой порт
```

```
  ╔══════════════════════════════════════════╗
  ║      Прокси успешно создан!             ║
  ╚══════════════════════════════════════════╝

  Клиент:  ivan
  Домен:   cloudflare.com (Fake TLS)
  IP:      YOUR_SERVER_IP
  Порт:    443
  Secret:  ee677b0daeb1d77040d847...

  tg:// ссылка:
  tg://proxy?server=YOUR_SERVER_IP&port=443&secret=ee677...

  QR-код:
  █████████████████████
  ██ ▄▄▄▄▄ █▀ █▀ ▄▄▄▄▄ ██
  ██ █   █ ██▄ ▀ █   █ ██
  ██ █▄▄▄█ █▀▀▄▄ █▄▄▄█ ██
  ██▄▄▄▄▄▄▄█▄▀ ▀▄▄▄▄▄▄▄██
  █████████████████████
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
| **Автобэкапы** | Перед каждым изменением |

### 🟣 Xray SOCKS5 (универсальный)
| Фича | Описание |
|------|----------|
| **Все приложения** | WhatsApp, Instagram, браузер, любые мессенджеры |
| **Авторизация** | Открытый или с логином/паролем |
| **UDP** | Голосовые звонки WhatsApp работают |
| **QR-код** | Для быстрого подключения |

### ⚙️ Система
| Фича | Описание |
|------|----------|
| **Healthcheck** | Cron каждые 5 минут — упавший прокси перезапускается сам |
| **TG уведомления** | Бот пишет когда прокси упал и восстановился |
| **Авто-rotate** | Секреты обновляются раз в неделю/месяц |
| **Firewall-помощник** | Автооткрытие портов в UFW/firewalld/iptables |
| **Таблица портов** | Видно что занято прямо перед выбором |
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

### WhatsApp через Xray SOCKS5
```
Настройки → Хранилище и данные → Прокси
Тип:    SOCKS5
Хост:   IP_сервера
Порт:   1080
```

### Android (системный — все приложения)
```
Настройки → WiFi → Прокси → Вручную
Хост: IP_сервера  |  Порт: 1080  |  Тип: SOCKS5
```

---

## 🌐 Домены для Fake TLS

<details>
<summary>🌍 Международные (32 домена) — нажми чтобы раскрыть</summary>

**Tech:** `google.com` `cloudflare.com` `microsoft.com` `apple.com` `amazon.com` `github.com` `stackoverflow.com` `gitlab.com`

**СМИ:** `wikipedia.org` `bbc.com` `cnn.com` `reuters.com` `nytimes.com` `theguardian.com` `bloomberg.com` `forbes.com`

**Развлечения:** `netflix.com` `twitch.tv` `discord.com` `zoom.us` `spotify.com` `reddit.com` `medium.com` `tumblr.com`

**Образование:** `coursera.org` `udemy.com` `khanacademy.org` `edx.org` `duolingo.com` `ted.com` `skillshare.com`

</details>

<details>
<summary>🇷🇺 Российские (29 доменов) — нажми чтобы раскрыть</summary>

**СМИ:** `lenta.ru` `rbc.ru` `ria.ru` `kommersant.ru` `vedomosti.ru` `iz.ru` `novayagazeta.ru` `meduza.io`

**Tech/IT:** `habr.com` `mail.ru` `yandex.ru` `vk.com` `2ch.hk` `pikabu.ru` `4pda.to` `3dnews.ru`

**Образование:** `stepik.org` `geekbrains.ru` `skillbox.ru` `hexlet.io` `netology.ru` `skillfactory.ru`

**Сервисы:** `gosuslugi.ru` `sberbank.ru` `tinkoff.ru` `avito.ru` `ozon.ru` `wildberries.ru` `kinopoisk.ru` `ivi.ru`

</details>

---

## 🛡 Требования

| | |
|---|---|
| **ОС** | Ubuntu 20.04+, Debian 10+, CentOS 7+, Fedora 36+, Rocky/AlmaLinux |
| **RAM** | от 512MB (1GB+ рекомендуется) |
| **Docker** | Устанавливается автоматически |
| **Права** | root / sudo |
| **Порты** | 443, 8443, 3128, 1080 или любой свой |

---

## 📋 Changelog

<details>
<summary>История версий</summary>

### v4.0 — Xray SOCKS5
- Добавлен Xray SOCKS5 (WhatsApp / универсальный прокси)
- Пункт "Установить всё сразу" (Telegram + Xray)
- Авторизация Xray (открытый / логин+пароль)
- QR-код для SOCKS5, инструкция по подключению в терминале

### v3.0 — Полная автоматизация
- Таблица статусов портов с firewall статусом
- Автооткрытие портов, блокировка занятых
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

<div align="center">

**Сделано с ❤️ для русскоязычного сообщества**

[⭐ Поставить звезду](https://github.com/ivanstudiya-cpu/mtproxy) · [🐛 Сообщить о баге](https://github.com/ivanstudiya-cpu/mtproxy/issues) · [💡 Предложить фичу](https://github.com/ivanstudiya-cpu/mtproxy/issues)

</div>
