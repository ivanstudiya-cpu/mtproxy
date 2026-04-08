# 🔒 MTProxy Manager — Telegram MTProxy с Fake TLS

![version](https://img.shields.io/badge/version-3.0-blue)
![bash](https://img.shields.io/badge/bash-5.0+-green)
![docker](https://img.shields.io/badge/docker-required-blue)
![license](https://img.shields.io/badge/license-MIT-brightgreen)
![platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian%20%7C%20CentOS-lightgrey)

> Bash-скрипт для быстрого развёртывания и управления MTProxy серверами для Telegram с маскировкой трафика под HTTPS (Fake TLS). Работает через Docker, устанавливается за одну команду.

---

## 📋 Changelog

### v3.0
- Добавлена таблица статусов портов перед выбором (процесс + firewall + прокси)
- Автооткрытие порта в firewall при выборе закрытого
- Порт 1080 (SOCKS) в списке выбора
- Уведомления в Telegram (бот пишет когда прокси упал/восстановился)
- Healthcheck через cron — автоперезапуск упавших контейнеров каждые 5 минут
- Авто-обновление секрета по расписанию (раз в неделю или месяц)
- Экспорт всех ссылок в файл одной командой
- Миграция на новый сервер — генерация готового bash-скрипта
- Firewall-помощник (UFW / firewalld / iptables)
- Авто-обновление скрипта с GitHub
- Статистика подключений по каждому прокси

### v2.0
- Rotate Secret с автобэкапом
- Автобэкапы перед любым деструктивным действием
- Лог всех действий в `/var/log/mtproxy.log`
- QR-коды для tg:// и https://t.me/proxy
- Start / Stop / Restart без ввода имён вручную
- Поддержка apt / yum / dnf
- 64 домена по категориям (российские и международные)

### v1.0
- Базовое создание MTProxy с Fake TLS через Docker
- Список прокси с QR-кодами

---

## ⚡ Быстрая установка

```bash
wget -O mtproxy.sh https://raw.githubusercontent.com/ivanstudiya-cpu/mtproxy/main/mtproxy.sh && chmod +x mtproxy.sh && sudo ./mtproxy.sh
```

После установки скрипт доступен глобально как команда `mtproxy`.

---

## 🎯 Возможности

### Основные
- **Fake TLS маскировка** — трафик выглядит как обычный HTTPS к реальному сайту. Провайдер не определяет прокси.
- **64 домена** для маскировки (российские и международные) по категориям + ввод своего.
- **QR-коды** — сразу два: `tg://` и `https://t.me/proxy` прямо в терминале.
- **Авто-установка зависимостей** — Docker, qrencode, jq ставятся сами.

### Безопасность и надёжность
- **Rotate Secret** — обновление секрета без пересоздания клиента вручную. Старый конфиг бэкапится автоматически.
- **Healthcheck (cron)** — каждые 5 минут проверяет что контейнеры живые и перезапускает упавшие.
- **Авто-обновление секрета** — cron-задача обновляет секреты по расписанию (раз в неделю или месяц).
- **Auto-backup** — перед каждым деструктивным действием конфиг сохраняется в `/etc/mtproxy/backups/`.
- **Защита от случайного удаления** — полный снос требует ввода слова `DELETE`.

### Мониторинг
- **Статистика подключений** — количество активных соединений по каждому прокси.
- **Сетевой трафик** — CPU, память, NetIO по каждому контейнеру.
- **Лог всех действий** — каждое действие пишется в `/var/log/mtproxy.log` с таймстампом.

### Уведомления
- **Telegram-бот уведомления** — пишет тебе в личку когда прокси упал и когда восстановился. Настраивается через @BotFather за 2 минуты.

### Удобство
- **Firewall-помощник** — автоматически открывает/закрывает нужный порт в UFW / firewalld / iptables.
- **Экспорт всех ссылок** — одна команда сохраняет все `tg://` и `https://` ссылки в файл.
- **Миграция на новый сервер** — генерирует готовый bash-скрипт для переноса всех прокси одной командой.
- **Авто-обновление скрипта** — проверяет GitHub и обновляется до новой версии.

---

## 📋 Меню управления

```
  1)  Добавить новый прокси
  2)  Список всех прокси
  3)  Детали / QR по клиенту
  4)  Статус, трафик и подключения
  5)  Start / Stop / Restart
  6)  Обновить секрет (rotate)
  7)  Экспорт всех ссылок в файл
  8)  Миграция на новый сервер
  9)  Firewall — управление портами
  10) Healthcheck / Автоперезапуск
  11) Авто-обновление секрета (cron)
  12) Уведомления в Telegram
  13) Обновить скрипт
  14) Просмотр лога
  15) Удалить прокси
  16) Полное удаление
  0)  Выход
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
/usr/local/bin/mtproxy            — глобальная команда
/etc/mtproxy/proxies.conf         — конфиг всех прокси
/etc/mtproxy/backups/             — автобэкапы
/etc/mtproxy/healthcheck.sh       — скрипт healthcheck (cron)
/etc/mtproxy/auto_rotate.sh       — скрипт авто-rotate (cron)
/etc/mtproxy/notify.conf          — конфиг Telegram-бота
/etc/mtproxy/export_links.txt     — экспорт ссылок
/var/log/mtproxy.log              — лог всех действий
```

---

## 🛡 Требования

- Сервер с публичным IP (VPS / выделенный)
- Linux: Ubuntu 20.04+, Debian 10+, CentOS 7+, Fedora 36+, Rocky/AlmaLinux
- root-доступ (`sudo`)
- Открытый порт (443, 8443, 3128 или любой другой)
- Docker устанавливается автоматически если не установлен

---

## 📝 Лицензия

MIT — используйте свободно.

---

> Скрипт предназначен для обхода блокировок Telegram в регионах с ограниченным доступом. Используйте ответственно и в соответствии с законодательством вашей страны.
