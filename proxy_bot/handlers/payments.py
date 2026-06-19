import logging
from html import escape

from aiogram import F, Router
from aiogram.types import (
    CallbackQuery, LabeledPrice, Message,
    PreCheckoutQuery, SuccessfulPayment,
)

from config import config
from keyboards.inline import back_kb, main_menu_kb
from services.proxy_service import (
    create_mtproxy, create_wireguard_client, create_xray,
)
from services.user_service import (
    confirm_payment, create_payment, create_subscription,
    get_or_create_user, get_plan, save_proxy,
)

router = Router()
logger = logging.getLogger(__name__)


def _h(value) -> str:
    return escape(str(value), quote=False)


# ─── Telegram Stars ─────────────────────────────────────────

@router.callback_query(F.data.startswith("pay_stars:"))
async def cb_pay_stars(cb: CallbackQuery):
    plan_id = int(cb.data.split(":")[1])
    plan = await get_plan(plan_id)
    if not plan:
        await cb.answer("Тариф не найден", show_alert=True)
        return

    await cb.message.answer_invoice(
        title=plan.name,
        description=plan.description or f"Прокси подписка на {plan.duration_days} дней",
        payload=f"plan:{plan_id}",
        currency="XTR",
        prices=[LabeledPrice(label=plan.name, amount=plan.price_stars)],
    )
    await cb.answer()


@router.pre_checkout_query()
async def pre_checkout(query: PreCheckoutQuery):
    """Telegram требует подтверждения перед списанием Stars."""
    await query.answer(ok=True)


@router.message(F.successful_payment)
async def successful_payment(msg: Message):
    """Оплата Stars прошла — создаём подписку и прокси."""
    payment: SuccessfulPayment = msg.successful_payment
    payload = payment.invoice_payload  # "plan:1"

    try:
        plan_id = int(payload.split(":")[1])
    except (IndexError, ValueError):
        logger.error("Bad payment payload: %s", payload)
        await msg.answer("❌ Ошибка обработки платежа. Обратись в поддержку.")
        return

    user = await get_or_create_user(
        telegram_id=msg.from_user.id,
        username=msg.from_user.username,
        full_name=msg.from_user.full_name,
    )
    plan = await get_plan(plan_id)
    if not plan:
        await msg.answer("❌ Тариф не найден. Обратись в поддержку.")
        return

    # Создаём запись платежа
    db_payment = await create_payment(
        user_id=user.id,
        plan_id=plan_id,
        subscription_id=None,
        amount=payment.total_amount,
        currency="XTR",
        provider="stars",
    )

    # Создаём подписку
    sub = await create_subscription(user_id=user.id, plan_id=plan_id)

    # Подтверждаем платёж
    await confirm_payment(db_payment.id, payment.telegram_payment_charge_id)

    await msg.answer(
        f"✅ <b>Оплата прошла!</b>\n\n"
        f"Создаю прокси для тебя... ⚙️\n"
        f"Это займёт 10-30 секунд.",
        parse_mode="HTML",
    )

    # Создаём прокси по протоколам из плана
    errors = []
    created = []

    for protocol in plan.protocols:
        try:
            if protocol == "mtproxy":
                result = await create_mtproxy(user.telegram_id)
            elif protocol == "xray":
                result = await create_xray(user.telegram_id)
            elif protocol == "wireguard":
                result = await create_wireguard_client(user.telegram_id)
            else:
                continue

            if result.success:
                await save_proxy(
                    subscription_id=sub.id,
                    proxy_type=result.proxy_type,
                    container_name=result.container_name,
                    client_name=result.client_name,
                    port=result.port,
                    secret=result.secret,
                    tg_link=result.tg_link,
                    config_data=result.config_data,
                )
                created.append(result)
            else:
                errors.append(f"{protocol}: {result.error}")
                logger.error("Proxy create failed %s: %s", protocol, result.error)

        except Exception as e:
            errors.append(f"{protocol}: {e}")
            logger.exception("Exception creating %s proxy", protocol)

    # Отправляем результат
    await _send_proxy_results(msg, created, plan)

    if errors:
        await msg.answer(
            f"⚠️ Не удалось создать некоторые прокси:\n" + "\n".join(errors) +
            f"\n\nОбратись в поддержку: @{config.support_username}",
            parse_mode="HTML",
        )


# ─── Отправка данных прокси клиенту ─────────────────────────

async def _send_proxy_results(msg: Message, results: list, plan) -> None:
    if not results:
        await msg.answer(
            "❌ Не удалось создать прокси. Обратись в поддержку.",
            reply_markup=back_kb("main_menu"),
        )
        return

    await msg.answer(
        f"🎉 <b>{_h(plan.name)}</b> активирован!\n\n"
        f"Ниже твои данные для подключения 👇",
        parse_mode="HTML",
    )

    for r in results:
        if r.proxy_type == "mtproxy":
            await msg.answer(
                f"📡 <b>Telegram MTProxy</b>\n\n"
                f"<b>Ссылка для подключения:</b>\n"
                f"<code>{_h(r.tg_link)}</code>\n\n"
                f"Просто нажми на ссылку — Telegram подключится автоматически.\n"
                f"Или перейди: Настройки → Конфиденциальность → Прокси",
                parse_mode="HTML",
                reply_markup=back_kb("main_menu"),
            )

        elif r.proxy_type == "xray":
            cd = r.config_data or {}
            host = cd.get("host", config.vps_host)
            socks_port = cd.get("socks_port", r.port)
            http_port = cd.get("http_port", "")
            user = cd.get("user", "")
            password = cd.get("password", "")
            auth_text = ""
            if user and password:
                auth_text = (
                    f"<b>Логин:</b> <code>{_h(user)}</code>\n"
                    f"<b>Пароль:</b> <code>{_h(password)}</code>\n\n"
                    f"<b>SOCKS5 URL:</b>\n"
                    f"<code>socks5://{_h(user)}:{_h(password)}@{_h(host)}:{_h(socks_port)}</code>\n\n"
                    f"<b>HTTP URL:</b>\n"
                    f"<code>http://{_h(user)}:{_h(password)}@{_h(host)}:{_h(http_port)}</code>\n\n"
                )
            await msg.answer(
                f"🟣 <b>Xray SOCKS5</b> (WhatsApp, Instagram)\n\n"
                f"<b>Хост:</b> <code>{_h(host)}</code>\n"
                f"<b>Порт SOCKS5:</b> <code>{_h(socks_port)}</code>\n"
                f"<b>Порт HTTP:</b> <code>{_h(http_port)}</code>\n"
                f"{auth_text}"
                f"<b>WhatsApp:</b> Настройки → Хранилище и данные → Прокси\n"
                f"Введи хост, HTTP-порт, логин и пароль выше.",
                parse_mode="HTML",
            )

        elif r.proxy_type == "wireguard":
            cd = r.config_data or {}
            config_text = cd.get("config", "")
            qr_text = cd.get("qr", "")

            await msg.answer(
                f"🟢 <b>WireGuard VPN</b> (весь трафик)\n\n"
                f"1. Установи приложение WireGuard из App Store / Play Store\n"
                f"2. Нажми <b>+</b> → <b>Сканировать QR</b>\n"
                f"3. Отсканируй QR ниже\n"
                f"4. Включи — весь трафик через сервер ✅",
                parse_mode="HTML",
            )

            if qr_text:
                await msg.answer(f"<pre>{_h(qr_text)}</pre>", parse_mode="HTML")

            if config_text:
                # Отправляем конфиг как файл
                from aiogram.types import BufferedInputFile
                conf_bytes = config_text.encode("utf-8")
                file = BufferedInputFile(conf_bytes, filename=f"wg_{msg.from_user.id}.conf")
                await msg.answer_document(
                    file,
                    caption="📄 WireGuard конфиг файл (для импорта вручную)",
                )
