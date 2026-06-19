import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from aiogram import Bot

from services.user_service import expire_subscriptions, get_expiring_soon

logger = logging.getLogger(__name__)
scheduler = AsyncIOScheduler(timezone="Europe/Moscow")


def setup_scheduler(bot: Bot) -> AsyncIOScheduler:

    @scheduler.scheduled_job("interval", minutes=30, id="check_expired")
    async def check_expired():
        """Помечает просроченные подписки и уведомляет пользователей."""
        try:
            expired_tg_ids = await expire_subscriptions()
            for tg_id in expired_tg_ids:
                try:
                    await bot.send_message(
                        tg_id,
                        "📭 <b>Твоя подписка истекла.</b>\n\n"
                        "Прокси отключены. Чтобы продолжить пользоваться — "
                        "обнови подписку.\n\n"
                        "Нажми /start чтобы выбрать тариф.",
                        parse_mode="HTML",
                    )
                except Exception as e:
                    logger.warning("Can't notify %d: %s", tg_id, e)

            if expired_tg_ids:
                logger.info("Expired %d subscriptions", len(expired_tg_ids))
        except Exception:
            logger.exception("check_expired failed")

    @scheduler.scheduled_job("cron", hour=10, minute=0, id="remind_expiring")
    async def remind_expiring():
        """Напоминает за 3 дня до истечения подписки."""
        try:
            expiring = await get_expiring_soon(days=3)
            for tg_id, sub in expiring:
                try:
                    await bot.send_message(
                        tg_id,
                        f"⚠️ <b>Подписка истекает через {sub.days_left} дн.</b>\n\n"
                        f"Не забудь продлить чтобы прокси не отключились.\n\n"
                        f"Нажми /start → Тарифы и подписка.",
                        parse_mode="HTML",
                    )
                except Exception as e:
                    logger.warning("Can't remind %d: %s", tg_id, e)
        except Exception:
            logger.exception("remind_expiring failed")

    return scheduler
