from dataclasses import dataclass
from dotenv import load_dotenv
import os

load_dotenv()

@dataclass
class Config:
    # Telegram
    bot_token: str
    admin_id: int
    bot_username: str
    support_username: str

    # VPS SSH
    vps_host: str
    vps_port: int
    vps_user: str
    vps_key_path: str | None
    vps_password: str | None
    vps_known_hosts: str | None

    # DB
    database_url: str

    # Payments
    crypto_bot_token: str | None
    yukassa_shop_id: str | None
    yukassa_secret_key: str | None


def load_config() -> Config:
    return Config(
        bot_token=os.environ["BOT_TOKEN"],
        admin_id=int(os.environ["ADMIN_ID"]),
        bot_username=os.getenv("BOT_USERNAME", "proxy_bot"),
        support_username=os.getenv("SUPPORT_USERNAME", ""),

        vps_host=os.environ["VPS_HOST"],
        vps_port=int(os.getenv("VPS_PORT", "22")),
        vps_user=os.getenv("VPS_USER", "root"),
        vps_key_path=os.getenv("VPS_KEY_PATH"),
        vps_password=os.getenv("VPS_PASSWORD"),
        vps_known_hosts=os.getenv("VPS_KNOWN_HOSTS"),

        database_url=os.getenv("DATABASE_URL", "sqlite+aiosqlite:///proxy_bot.db"),

        crypto_bot_token=os.getenv("CRYPTO_BOT_TOKEN"),
        yukassa_shop_id=os.getenv("YUKASSA_SHOP_ID"),
        yukassa_secret_key=os.getenv("YUKASSA_SECRET_KEY"),
    )


config = load_config()
