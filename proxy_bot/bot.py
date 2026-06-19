import asyncio
import logging

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode

from config import config
from database import init_db
from handlers import admin, main, payments
from scheduler import setup_scheduler

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


async def main_loop():
    logger.info("Starting Proxy Bot...")

    # Инициализируем БД
    await init_db()
    logger.info("Database ready")

    bot = Bot(
        token=config.bot_token,
        default=DefaultBotProperties(parse_mode=ParseMode.HTML),
    )
    dp = Dispatcher()

    # Подключаем роутеры
    dp.include_router(admin.router)
    dp.include_router(payments.router)
    dp.include_router(main.router)

    # Планировщик
    scheduler = setup_scheduler(bot)
    scheduler.start()
    logger.info("Scheduler started")

    # Запуск
    logger.info("Bot started: @%s", config.bot_username)
    try:
        await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
    finally:
        scheduler.shutdown()
        await bot.session.close()


if __name__ == "__main__":
    asyncio.run(main_loop())
