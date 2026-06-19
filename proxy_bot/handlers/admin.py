import logging
from aiogram import F, Router
from aiogram.filters import Command
from aiogram.types import Message
from sqlalchemy import func, select

from config import config
from database import AsyncSessionFactory
from models import Payment, Subscription, User
from services.user_service import get_all_plans

router = Router()
logger = logging.getLogger(__name__)


def is_admin(user_id: int) -> bool:
    return user_id == config.admin_id


@router.message(Command("admin"))
async def cmd_admin(msg: Message):
    if not is_admin(msg.from_user.id):
        return

    async with AsyncSessionFactory() as session:
        users_count = (await session.execute(func.count(User.id))).scalar()
        active_subs = (await session.execute(
            select(func.count(Subscription.id)).where(Subscription.status == "active")
        )).scalar()
        total_paid = (await session.execute(
            select(func.sum(Payment.amount)).where(Payment.status == "paid", Payment.currency == "XTR")
        )).scalar() or 0

    text = (
        f"🛠 <b>Админ панель</b>\n\n"
        f"👥 Пользователей: <b>{users_count}</b>\n"
        f"✅ Активных подписок: <b>{active_subs}</b>\n"
        f"⭐ Всего получено Stars: <b>{total_paid}</b>\n\n"
        f"<b>Команды:</b>\n"
        f"/stats — статистика\n"
        f"/broadcast — рассылка\n"
        f"/give_sub [user_id] [plan_id] — выдать подписку"
    )
    await msg.answer(text, parse_mode="HTML")


@router.message(Command("stats"))
async def cmd_stats(msg: Message):
    if not is_admin(msg.from_user.id):
        return

    async with AsyncSessionFactory() as session:
        users_total = (await session.execute(select(func.count(User.id)))).scalar()
        subs_active = (await session.execute(
            select(func.count(Subscription.id)).where(Subscription.status == "active")
        )).scalar()
        subs_expired = (await session.execute(
            select(func.count(Subscription.id)).where(Subscription.status == "expired")
        )).scalar()
        payments_total = (await session.execute(
            select(func.count(Payment.id)).where(Payment.status == "paid")
        )).scalar()
        stars_total = (await session.execute(
            select(func.sum(Payment.amount)).where(
                Payment.status == "paid", Payment.currency == "XTR"
            )
        )).scalar() or 0

    plans = await get_all_plans()
    plans_text = "\n".join(f"  {p.name}: {p.price_stars}⭐" for p in plans)

    await msg.answer(
        f"📊 <b>Статистика</b>\n\n"
        f"👥 Всего пользователей: <b>{users_total}</b>\n"
        f"✅ Активных подписок: <b>{subs_active}</b>\n"
        f"❌ Истёкших: <b>{subs_expired}</b>\n"
        f"💳 Успешных оплат: <b>{payments_total}</b>\n"
        f"⭐ Stars получено: <b>{stars_total}</b>\n\n"
        f"<b>Тарифы:</b>\n{plans_text}",
        parse_mode="HTML",
    )


@router.message(Command("broadcast"))
async def cmd_broadcast(msg: Message):
    if not is_admin(msg.from_user.id):
        return

    # /broadcast Текст сообщения
    text = msg.text.replace("/broadcast", "").strip()
    if not text:
        await msg.answer("Использование: /broadcast Текст сообщения")
        return

    async with AsyncSessionFactory() as session:
        result = await session.execute(select(User.telegram_id).where(User.is_banned == False))
        user_ids = [row[0] for row in result.all()]

    sent = 0
    failed = 0
    for uid in user_ids:
        try:
            await msg.bot.send_message(uid, text, parse_mode="HTML")
            sent += 1
        except Exception:
            failed += 1

    await msg.answer(f"✅ Отправлено: {sent}\n❌ Не доставлено: {failed}")
