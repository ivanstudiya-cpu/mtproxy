# Proxy Bot — бот продаж прокси-подписок

Telegram бот для автоматической продажи и выдачи прокси (MTProxy, Xray SOCKS5, WireGuard VPN).

## Структура проекта

```
proxy_bot/
├── bot.py                    # точка входа
├── config.py                 # настройки из .env
├── database.py               # подключение к БД, seed тарифов
├── models.py                 # SQLAlchemy модели
├── scheduler.py              # APScheduler задачи
├── requirements.txt
├── .env.example
├── handlers/
│   ├── main.py               # /start, тарифы, профиль
│   ├── payments.py           # Telegram Stars оплата
│   └── admin.py              # /admin, /stats, /broadcast
├── services/
│   ├── proxy_service.py      # SSH → VPS, создание прокси
│   └── user_service.py       # CRUD пользователей/подписок
└── keyboards/
    └── inline.py             # все inline клавиатуры
```

## Установка

```bash
# Клонируй репо
git clone https://github.com/ivan-yurich/mtproxy
cd proxy_bot

# Виртуальное окружение
python3 -m venv venv
source venv/bin/activate

# Зависимости
pip install -r requirements.txt

# Конфиг
cp .env.example .env
nano .env   # заполни BOT_TOKEN, ADMIN_ID, VPS_HOST, VPS_KEY_PATH

# SSH host key pinning
ssh-keyscan -p "$VPS_PORT" "$VPS_HOST" >> ~/.ssh/known_hosts

# Запуск
python bot.py
```

## Безопасность

- SSH по умолчанию использует строгую проверку host key. Для первого доверенного подключения добавь сервер в `VPS_KNOWN_HOSTS` через `ssh-keyscan`.
- Xray SOCKS5/HTTP создаётся только с логином и паролем. Публичный `noauth` режим в боте отключён.
- Remote shell-команды валидируют имена, порты и домены, а файлы конфигурации пишутся без heredoc-инъекций.

## Деплой через systemd

```ini
# /etc/systemd/system/proxy-bot.service
[Unit]
Description=Proxy Sales Bot
After=network.target

[Service]
User=root
WorkingDirectory=/root/proxy_bot
ExecStart=/root/proxy_bot/venv/bin/python bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now proxy-bot
journalctl -u proxy-bot -f
```

## Добавить оплату

### Telegram Stars (уже готово)
Работает из коробки. Stars автоматически конвертируются Telegram.

### CryptoBot (добавить позже)
1. Напиши @CryptoBot → /pay → создай приложение
2. Получи токен → добавь в .env CRYPTO_BOT_TOKEN
3. Реализуй `handlers/crypto_payment.py`

### ЮKassa (добавить позже)
1. Зарегистрируйся на yookassa.ru (нужно ИП/самозанятость)
2. Получи shop_id и secret_key → в .env
3. Реализуй webhook в `handlers/yukassa.py`
