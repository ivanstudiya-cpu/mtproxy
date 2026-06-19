from aiogram import F, Router
from aiogram.filters import CommandStart
from aiogram.types import CallbackQuery, Message

from config import config
from keyboards.inline import (
    back_kb, main_menu_kb, my_proxies_kb,
    plan_detail_kb, plans_kb,
)
from models import Subscription
from services.user_service import (
    get_active_subscription, get_all_plans, get_or_create_user,
)

router = Router()


# ─── /start ─────────────────────────────────────────────────

@router.message(CommandStart())
async def cmd_start(msg: Message):
    user = await get_or_create_user(
        telegram_id=msg.from_user.id,
        username=msg.from_user.username,
        full_name=msg.from_user.full_name,
    )

    name = msg.from_user.first_name or "друг"
    sub = await get_active_subscription(user.id)

    if sub:
        status_line = (
            f"✅ Подписка активна · ⏳ Осталось {sub.days_left} дн."
        )
    else:
        status_line = "📭 Подписки нет · Выбери тариф ниже"

    text = (
        f"👋 Привет, <b>{name}</b>!\n\n"
        f"🔒 <b>Messenger Proxy Manager</b>\n"
        f"Telegram MTProxy + Xray SOCKS5 + WireGuard VPN\n\n"
        f"{status_line}"
    )
    await msg.answer(text, parse_mode="HTML", reply_markup=main_menu_kb())


@router.callback_query(F.data == "main_menu")
async def cb_main_menu(cb: CallbackQuery):
    user = await get_or_create_user(
        telegram_id=cb.from_user.id,
        username=cb.from_user.username,
        full_name=cb.from_user.full_name,
    )
    sub = await get_active_subscription(user.id)
    name = cb.from_user.first_name or "друг"

    status_line = (
        f"✅ Подписка активна · ⏳ Осталось {sub.days_left} дн."
        if sub else
        "📭 Подписки нет · Выбери тариф ниже"
    )

    text = (
        f"👋 Привет, <b>{name}</b>!\n\n"
        f"🔒 <b>Messenger Proxy Manager</b>\n"
        f"Telegram MTProxy + Xray SOCKS5 + WireGuard VPN\n\n"
        f"{status_line}"
    )
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=main_menu_kb())


# ─── Тарифы ─────────────────────────────────────────────────

@router.callback_query(F.data == "plans")
async def cb_plans(cb: CallbackQuery):
    plans = await get_all_plans()
    text = (
        "📦 <b>Выбери тариф</b>\n\n"
        "🥉 <b>Базовый</b> — Telegram MTProxy\n"
        "🥈 <b>Стандарт</b> — MTProxy + Xray SOCKS5 (WhatsApp)\n"
        "🥇 <b>Премиум</b> — MTProxy + Xray + WireGuard VPN\n\n"
        "Все тарифы на <b>30 дней</b>. После оплаты — прокси выдаётся автоматически."
    )
    await cb.message.edit_text(
        text, parse_mode="HTML", reply_markup=plans_kb(plans)
    )


@router.callback_query(F.data.startswith("plan:"))
async def cb_plan_detail(cb: CallbackQuery):
    plan_id = int(cb.data.split(":")[1])
    plans = await get_all_plans()
    plan = next((p for p in plans if p.id == plan_id), None)
    if not plan:
        await cb.answer("Тариф не найден", show_alert=True)
        return

    protocols_text = {
        "mtproxy": "📡 Telegram MTProxy (Fake TLS)",
        "xray": "🟣 Xray SOCKS5 (WhatsApp, Instagram, браузер)",
        "wireguard": "🟢 WireGuard VPN (весь трафик, все приложения)",
    }
    protos = "\n".join(
        f"  • {protocols_text.get(p, p)}" for p in plan.protocols
    )

    text = (
        f"<b>{plan.name}</b>\n\n"
        f"📋 <b>Включено:</b>\n{protos}\n\n"
        f"📱 Устройств: <b>{plan.max_devices}</b>\n"
        f"📅 Срок: <b>{plan.duration_days} дней</b>\n\n"
        f"💰 <b>Стоимость:</b>\n"
        f"  • {plan.price_stars} ⭐ Telegram Stars\n"
        f"  • {plan.price_rub // 100}₽ (криптой)\n\n"
        f"Выбери способ оплаты:"
    )
    await cb.message.edit_text(
        text, parse_mode="HTML", reply_markup=plan_detail_kb(plan_id)
    )


# ─── Мои прокси ─────────────────────────────────────────────

@router.callback_query(F.data == "my_proxies")
async def cb_my_proxies(cb: CallbackQuery):
    user = await get_or_create_user(
        telegram_id=cb.from_user.id,
        username=cb.from_user.username,
        full_name=cb.from_user.full_name,
    )
    sub = await get_active_subscription(user.id)

    if not sub:
        await cb.message.edit_text(
            "📭 У тебя нет активной подписки.\n\nВыбери тариф чтобы начать!",
            reply_markup=back_kb("plans"),
        )
        return

    if not sub.proxies:
        await cb.message.edit_text(
            "⚙️ Прокси ещё создаются... Попробуй через минуту.",
            reply_markup=back_kb("main_menu"),
        )
        return

    text = (
        f"📡 <b>Твои прокси</b>\n\n"
        f"Тариф: {sub.plan.name}\n"
        f"⏳ Истекает: {sub.expires_at.strftime('%d.%m.%Y')}"
    )
    await cb.message.edit_text(
        text, parse_mode="HTML", reply_markup=my_proxies_kb(sub)
    )


# ─── Профиль ────────────────────────────────────────────────

@router.callback_query(F.data == "profile")
async def cb_profile(cb: CallbackQuery):
    user = await get_or_create_user(
        telegram_id=cb.from_user.id,
        username=cb.from_user.username,
        full_name=cb.from_user.full_name,
    )
    sub = await get_active_subscription(user.id)

    sub_text = (
        f"✅ <b>{sub.plan.name}</b>\n"
        f"   Истекает: {sub.expires_at.strftime('%d.%m.%Y')} "
        f"(осталось {sub.days_left} дн.)"
        if sub else
        "📭 Нет активной подписки"
    )

    text = (
        f"👤 <b>Профиль</b>\n\n"
        f"ID: <code>{cb.from_user.id}</code>\n"
        f"Имя: {cb.from_user.full_name}\n"
        f"Аккаунт с: {user.created_at.strftime('%d.%m.%Y')}\n\n"
        f"📦 <b>Подписка:</b>\n{sub_text}"
    )
    await cb.message.edit_text(
        text, parse_mode="HTML", reply_markup=back_kb("main_menu")
    )


# ─── Помощь ─────────────────────────────────────────────────

@router.callback_query(F.data == "help")
async def cb_help(cb: CallbackQuery):
    text = (
        "❓ <b>Как подключиться</b>\n\n"
        "<b>Telegram MTProxy:</b>\n"
        "Перейди по ссылке tg:// — Telegram подключится сам.\n\n"
        "<b>WhatsApp через Xray:</b>\n"
        "Настройки → Хранилище и данные → Прокси\n"
        "Хост: IP сервера, Порт: из твоих данных\n\n"
        "<b>WireGuard VPN:</b>\n"
        "1. Установи приложение WireGuard\n"
        "2. Нажми + → Сканировать QR-код\n"
        "3. Включи VPN — весь трафик через сервер ✅\n\n"
        "Вопросы? Пиши в поддержку 👇"
    )
    await cb.message.edit_text(
        text, parse_mode="HTML", reply_markup=back_kb("main_menu")
    )


@router.callback_query(F.data == "support")
async def cb_support(cb: CallbackQuery):
    text = (
        f"💬 <b>Поддержка</b>\n\n"
        f"Пиши сюда: @{config.support_username}\n\n"
        f"Мы ответим в течение нескольких часов."
    )
    await cb.message.edit_text(
        text, parse_mode="HTML", reply_markup=back_kb("main_menu")
    )
