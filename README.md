<div align="center">

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&size=28&duration=3000&pause=1000&color=00D4FF&center=true&vCenter=true&width=700&lines=Messenger+Proxy+Manager+v4.9;Telegram+%2B+WhatsApp+%2B+WireGuard+VPN;Deploy+in+60+seconds+on+any+VPS" alt="Typing SVG" />

<br/>

[![Version](https://img.shields.io/badge/версия-4.9-00D4FF?style=for-the-badge&logo=github)](https://github.com/ivanstudiya-cpu/mtproxy/releases)
[![License](https://img.shields.io/badge/лицензия-MIT-22C55E?style=for-the-badge)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-required-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docker.com)
[![Stars](https://img.shields.io/github/stars/ivanstudiya-cpu/mtproxy?style=for-the-badge&color=FFD700&logo=github)](https://github.com/ivanstudiya-cpu/mtproxy/stargazers)
[![Shell](https://img.shields.io/badge/bash-5.0+-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)

<br/>

**Один bash-скрипт. Три протокола. Работает за 60 секунд.**

Telegram MTProxy с Fake TLS + Xray SOCKS5 + WireGuard VPN на любом VPS.
Полное управление из терминала и Telegram-бота.

<br/>

[🚀 Быстрый старт](#-быстрый-старт) •
[📋 Возможности](#-возможности) •
[📱 Подключение](#-подключение-на-телефоне) •
[🔐 Безопасность](#-безопасность) •
[📖 Changelog](#-changelog)

</div>

---

## 🤔 Зачем это нужно?

Если ты живёшь там, где блокируют мессенджеры — этот скрипт решает проблему раз и навсегда. Никаких платных VPN, никаких сторонних сервисов. Только твой VPS и один скрипт.

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   Telegram заблокирован?   →  MTProxy Fake TLS      ✅ Работает │
│   WhatsApp не открывается? →  WireGuard VPN         ✅ Работает │
│   Instagram, браузер?      →  Xray SOCKS5           ✅ Работает │
│   Нужно на всём телефоне?  →  WireGuard VPN         ✅ Работает │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Быстрый старт

```bash
wget -O mtproxy.sh https://raw.githubusercontent.com/ivanstudiya-cpu/mtproxy/main/mtproxy.sh \
  && chmod +x mtproxy.sh \
  && sudo ./mtproxy.sh
```

После установки скрипт доступен глобально:

```bash
mtproxy   # запустить из любого места
```

### Требования

| | |
|---|---|
| **ОС** | Ubuntu 20.04+ · Debian 10+ · CentOS 7+ · Rocky/AlmaLinux |
| **RAM** | от 512 MB (рекомендуется 1 GB+) |
| **Доступ** | root / sudo |
| **Docker** | устанавливается автоматически |

---

## 📋 Возможности

### Интерфейс

```
  ╔══════════════════════════════════════════════════════╗
  ║     Messenger Proxy Manager v4.9                    ║
  ║     Telegram MTProxy + Xray SOCKS5                  ║
  ╚══════════════════════════════════════════════════════╝

  ── Telegram MTProxy (Fake TLS) ──────────────────────
  1)  Добавить новый MTProxy
  2)  Список всех прокси
  3)  Детали / QR по клиенту
  4)  Статус, трафик и подключения
  5)  Start / Stop / Restart
  6)  Обновить секрет (rotate)
  7)  Экспорт всех ссылок в файл
  8)  Миграция на новый сервер

  ── Xray SOCKS5 (WhatsApp / универсальный) ───────────
  9)  Меню Xray SOCKS5

  ── WireGuard VPN (весь трафик) ──────────────────────
  20) Меню WireGuard VPN

  ── Установить всё сразу ─────────────────────────────
  10) Установить Telegram + Xray

  ── Telegram Бот ─────────────────────────────────────
  19) Бот управления (add/delete/list/qr)

  ── Система ──────────────────────────────────────────
  11) Firewall          12) Healthcheck
  13) Авто-rotate       14) TG-уведомления
  15) Обновить скрипт   16) Просмотр лога
  17) Удалить MTProxy   18) Полное удаление
```

---

### 🔵 Telegram MTProxy

Встроенная поддержка в Telegram — пользователь просто переходит по ссылке, никакого отдельного приложения.

| Фича | Описание |
|------|----------|
| **Fake TLS** | Трафик маскируется под HTTPS к настоящему сайту |
| **64 домена** | Google, Cloudflare, VK, Habr, RBC и другие |
| **QR-коды** | `tg://` и `https://t.me/proxy` прямо в терминале |
| **Несколько клиентов** | Каждый на своём порту с отдельным секретом |
| **Rotate Secret** | Смена секрета без пересоздания контейнера |
| **Авто-rotate** | Cron обновляет секреты раз в неделю или месяц |
| **Автобэкапы** | `.bak` файл перед каждым изменением |
| **Миграция** | Перенос всех прокси на новый сервер одной командой |

**Как выглядит созданный прокси:**

```
  ╔══════════════════════════════════════════╗
  ║      Прокси успешно создан!             ║
  ╚══════════════════════════════════════════╝

  Клиент:  ivan
  Домен:   cloudflare.com (Fake TLS)
  IP:      78.17.134.110
  Порт:    443
  Secret:  ee677b0daeb1d77040d847...

  tg://proxy?server=78.17.134.110&port=443&secret=ee677...

  QR:  ████████████████████
       ██ ▄▄▄▄▄ █▀█▀██▄▄▄ ██
       ██ █   █ ██▄▀ █   █ ██
       ██ █▄▄▄█ █▀▀▄▄█▄▄▄█ ██
       ████████████████████
```

---

### 🟣 Xray SOCKS5

Универсальный прокси для любых приложений. Работает там, где обычный MTProxy не поможет.

| Фича | Описание |
|------|----------|
| **Все приложения** | WhatsApp, Instagram, браузер, любые мессенджеры |
| **Порт 8443** | Альтернативный HTTPS — редко блокируется провайдерами |
| **HTTP прокси** | Второй порт для приложений без поддержки SOCKS5 |
| **Авторизация** | Открытый режим или логин + пароль |
| **QR-код** | Быстрое подключение в один скан |
| **Статус и трафик** | CPU, RAM, сетевой трафик в реальном времени |

---

### 🟢 WireGuard VPN

Самый надёжный вариант — весь трафик телефона идёт через сервер. Не нужно настраивать прокси в каждом приложении.

| Фича | Описание |
|------|----------|
| **Весь трафик** | WhatsApp, любые приложения без настройки в каждом |
| **Порт 53/UDP** | DNS-порт по умолчанию — не блокируется WiFi и операторами |
| **QR импорт** | Сканируешь QR в приложении WireGuard — готово |
| **Несколько клиентов** | Отдельный конфиг для телефона, планшета, ноутбука |
| **Фикс Docker NAT** | Явные iptables правила — работает рядом с Docker |
| **Управление из меню** | Добавить/удалить клиента, показать QR в любой момент |

> **Почему порт 53?**
> Стандартный порт WireGuard (51820/UDP) блокируется многими домашними роутерами и мобильными операторами. Порт 53 — это DNS, его не трогает никто.

---

### ⚙️ Автоматизация и мониторинг

| Фича | Описание |
|------|----------|
| **Healthcheck** | Cron каждые 5 минут — упавший прокси перезапускается сам |
| **TG уведомления** | Бот пишет когда прокси упал и когда восстановился |
| **Telegram бот** | `/add` `/delete` `/list` `/status` `/qr` `/restart` |
| **Firewall-помощник** | Автооткрытие портов в UFW / firewalld / iptables |
| **Экспорт ссылок** | Все `tg://` ссылки в один файл одной командой |
| **Авто-обновление** | Скрипт обновляется с GitHub с бэкапом текущей версии |
| **Логирование** | Все события пишутся в `/var/log/mtproxy.log` |

---

## 📱 Подключение на телефоне

### Telegram — 30 секунд

```
1. Скрипт создаёт ссылку: tg://proxy?server=IP&port=443&secret=...
2. Открой ссылку на телефоне — Telegram спросит "Подключиться?"
3. Нажми "Подключить" ✅
```

Или отсканируй QR-код прямо из терминала.

---

### WhatsApp и всё остальное — WireGuard ⭐ рекомендуется

**На сервере:**
```bash
mtproxy
# → 20) Меню WireGuard VPN
# → 1)  Установить WireGuard        (порт 53 по умолчанию)
# → 2)  Добавить клиента + QR
```

**На телефоне:**
1. Установи [WireGuard](https://play.google.com/store/apps/details?id=com.wireguard.android) из Play Store / App Store
2. Нажми `+` → `Сканировать QR-код`
3. Отсканируй QR из терминала
4. Включи тумблер — весь трафик идёт через сервер ✅

---

### WhatsApp через Xray (альтернатива)

```
Настройки WhatsApp → Хранилище и данные → Прокси
Хост: IP_сервера   Порт: 8443
```

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

## 🔐 Безопасность

Начиная с v4.6 скрипт прошёл аудит безопасности. Основные улучшения:

```
✅ chmod 600 на все конфиги и лог-файлы
✅ source заменён на grep+cut — нет выполнения кода из файлов конфига
✅ Секреты MTProxy не пишутся в лог
✅ Пароли Xray хранятся в base64 — символ | не ломает парсинг
✅ Валидация пользовательского ввода во всех меню
✅ Exponential backoff в Telegram боте при сетевых ошибках
✅ Проверка зависимостей (python3, curl, jq) при установке
✅ Безопасная установка при запуске через curl | bash
```

---

## 📖 Changelog

<details>
<summary>Все версии</summary>

### v4.9 — WireGuard VPN
- ✨ WireGuard VPN — весь трафик устройства через сервер
- ✨ Порт 53/UDP по умолчанию — обходит блокировки WiFi и операторов
- ✨ QR-код для импорта клиента одним сканированием
- 🔧 Фикс конфликта NAT с Docker (явные iptables правила для 10.8.0.0/24)
- ✨ Управление клиентами из меню (добавить/удалить/QR)

### v4.7 — Xray порт
- 🔧 Порт Xray по умолчанию изменён с 1080 на 8443
- ✨ Меню выбора порта при установке Xray

### v4.6 — Аудит безопасности
- 🔒 `source` заменён на `grep+cut` во всех местах чтения конфигов
- 🔒 Секрет MTProxy убран из логов авто-rotate
- 🔒 `chmod 600` на лог-файл при создании
- 🔒 Валидация IDX во всех меню выбора контейнера
- 🔒 Пароли Xray в base64
- 🔒 Exponential backoff в Telegram боте

### v4.5 — Telegram бот
- ✨ Бот управления прокси из Telegram
- ✨ Команды: `/add` `/delete` `/list` `/status` `/qr` `/restart`
- ✨ Admin-only фильтр по chat_id

### v4.0 — Xray SOCKS5
- ✨ Xray SOCKS5 для WhatsApp и универсального использования
- ✨ Пункт "Установить всё сразу"
- ✨ QR-код для SOCKS5

### v3.0 — Автоматизация
- ✨ TG уведомления, healthcheck, авто-rotate по cron
- ✨ Экспорт ссылок, миграция, авто-обновление

### v2.0 — Управление
- ✨ Rotate Secret, QR-коды, 64 домена для Fake TLS

### v1.0 — Старт
- ✨ Базовый MTProxy с Fake TLS через Docker

</details>

---

## 🤝 Помочь проекту

Если скрипт помог — **поставь ⭐ на GitHub!**
Это помогает другим найти проект и мотивирует развивать его дальше.

Нашёл баг или есть идея? [Открывай Issue](https://github.com/ivanstudiya-cpu/mtproxy/issues) — разберёмся!

---

<div align="center">

**Сделано с ❤️ для русскоязычного сообщества**

[⭐ Поставить звезду](https://github.com/ivanstudiya-cpu/mtproxy) · [🐛 Баг](https://github.com/ivanstudiya-cpu/mtproxy/issues) · [💡 Идея](https://github.com/ivanstudiya-cpu/mtproxy/issues)

</div>
