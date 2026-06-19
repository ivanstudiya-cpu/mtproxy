from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup
from aiogram.utils.keyboard import InlineKeyboardBuilder

from models import Plan, Subscription


def main_menu_kb() -> InlineKeyboardMarkup:
    builder = InlineKeyboardBuilder()
    builder.row(
        InlineKeyboardButton(text="📦 Тарифы и подписка", callback_data="plans"),
    )
    builder.row(
        InlineKeyboardButton(text="📡 Мои прокси", callback_data="my_proxies"),
        InlineKeyboardButton(text="👤 Профиль", callback_data="profile"),
    )
    builder.row(
        InlineKeyboardButton(text="❓ Помощь", callback_data="help"),
        InlineKeyboardButton(text="💬 Поддержка", callback_data="support"),
    )
    return builder.as_markup()


def plans_kb(plans: list[Plan]) -> InlineKeyboardMarkup:
    builder = InlineKeyboardBuilder()
    for plan in plans:
        builder.row(
            InlineKeyboardButton(
                text=f"{plan.name} — {plan.price_stars}⭐ / {plan.price_rub // 100}₽",
                callback_data=f"plan:{plan.id}",
            )
        )
    builder.row(InlineKeyboardButton(text="◀️ Назад", callback_data="main_menu"))
    return builder.as_markup()


def plan_detail_kb(plan_id: int) -> InlineKeyboardMarkup:
    builder = InlineKeyboardBuilder()
    builder.row(
        InlineKeyboardButton(text="⭐ Оплатить Stars", callback_data=f"pay_stars:{plan_id}"),
    )
    builder.row(
        InlineKeyboardButton(text="₿ Оплатить криптой", callback_data=f"pay_crypto:{plan_id}"),
    )
    builder.row(InlineKeyboardButton(text="◀️ Назад к тарифам", callback_data="plans"))
    return builder.as_markup()


def my_proxies_kb(sub: Subscription) -> InlineKeyboardMarkup:
    builder = InlineKeyboardBuilder()
    for proxy in sub.proxies:
        label = {"mtproxy": "📡 MTProxy", "xray": "🟣 Xray SOCKS5", "wireguard": "🟢 WireGuard"}
        builder.row(
            InlineKeyboardButton(
                text=label.get(proxy.proxy_type, proxy.proxy_type),
                callback_data=f"proxy_detail:{proxy.id}",
            )
        )
    builder.row(
        InlineKeyboardButton(text="🔄 Обновить", callback_data="my_proxies"),
        InlineKeyboardButton(text="◀️ Меню", callback_data="main_menu"),
    )
    return builder.as_markup()


def proxy_detail_kb(proxy_id: int, proxy_type: str) -> InlineKeyboardMarkup:
    builder = InlineKeyboardBuilder()
    if proxy_type == "mtproxy":
        builder.row(
            InlineKeyboardButton(text="🔗 Ссылка подключения", callback_data=f"proxy_link:{proxy_id}"),
        )
    if proxy_type == "wireguard":
        builder.row(
            InlineKeyboardButton(text="📷 QR-код", callback_data=f"proxy_qr:{proxy_id}"),
            InlineKeyboardButton(text="📄 Конфиг файл", callback_data=f"proxy_config:{proxy_id}"),
        )
    builder.row(InlineKeyboardButton(text="◀️ Назад", callback_data="my_proxies"))
    return builder.as_markup()


def back_kb(callback: str = "main_menu") -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[[InlineKeyboardButton(text="◀️ Назад", callback_data=callback)]]
    )


def confirm_payment_kb(plan_id: int, provider: str) -> InlineKeyboardMarkup:
    builder = InlineKeyboardBuilder()
    builder.row(
        InlineKeyboardButton(text="✅ Подтвердить", callback_data=f"confirm_pay:{plan_id}:{provider}"),
        InlineKeyboardButton(text="❌ Отмена", callback_data="plans"),
    )
    return builder.as_markup()
