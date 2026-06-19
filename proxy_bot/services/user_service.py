from datetime import datetime, timedelta
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from database import AsyncSessionFactory
from models import Payment, Plan, Proxy, Subscription, User


async def get_or_create_user(
    telegram_id: int,
    username: str | None,
    full_name: str | None,
) -> User:
    async with AsyncSessionFactory() as session:
        result = await session.execute(
            select(User).where(User.telegram_id == telegram_id)
        )
        user = result.scalar_one_or_none()

        if user:
            user.username = username
            user.full_name = full_name
            user.last_seen = datetime.utcnow()
            await session.commit()
            return user

        user = User(
            telegram_id=telegram_id,
            username=username,
            full_name=full_name,
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user


async def get_active_subscription(user_id: int) -> Subscription | None:
    async with AsyncSessionFactory() as session:
        result = await session.execute(
            select(Subscription)
            .where(
                Subscription.user_id == user_id,
                Subscription.status == "active",
                Subscription.expires_at > datetime.utcnow(),
            )
            .options(selectinload(Subscription.plan), selectinload(Subscription.proxies))
            .order_by(Subscription.expires_at.desc())
        )
        return result.scalar_one_or_none()


async def get_all_plans() -> list[Plan]:
    async with AsyncSessionFactory() as session:
        result = await session.execute(
            select(Plan)
            .where(Plan.is_active == True)
            .order_by(Plan.sort_order)
        )
        return list(result.scalars().all())


async def get_plan(plan_id: int) -> Plan | None:
    async with AsyncSessionFactory() as session:
        result = await session.execute(select(Plan).where(Plan.id == plan_id))
        return result.scalar_one_or_none()


async def create_subscription(user_id: int, plan_id: int) -> Subscription:
    plan = await get_plan(plan_id)
    if not plan:
        raise ValueError(f"Plan {plan_id} not found")

    async with AsyncSessionFactory() as session:
        sub = Subscription(
            user_id=user_id,
            plan_id=plan_id,
            status="active",
            expires_at=datetime.utcnow() + timedelta(days=plan.duration_days),
        )
        session.add(sub)
        await session.commit()
        await session.refresh(sub)
        return sub


async def save_proxy(
    subscription_id: int,
    proxy_type: str,
    container_name: str | None,
    client_name: str | None,
    port: int | None,
    secret: str | None,
    tg_link: str | None,
    config_data: dict | None,
) -> Proxy:
    async with AsyncSessionFactory() as session:
        proxy = Proxy(
            subscription_id=subscription_id,
            proxy_type=proxy_type,
            container_name=container_name,
            client_name=client_name,
            port=port,
            secret=secret,
            tg_link=tg_link,
            config_data=config_data,
        )
        session.add(proxy)
        await session.commit()
        await session.refresh(proxy)
        return proxy


async def create_payment(
    user_id: int,
    plan_id: int,
    subscription_id: int | None,
    amount: int,
    currency: str,
    provider: str,
) -> Payment:
    async with AsyncSessionFactory() as session:
        payment = Payment(
            user_id=user_id,
            plan_id=plan_id,
            subscription_id=subscription_id,
            amount=amount,
            currency=currency,
            provider=provider,
            status="pending",
        )
        session.add(payment)
        await session.commit()
        await session.refresh(payment)
        return payment


async def confirm_payment(payment_id: int, provider_payment_id: str) -> Payment | None:
    async with AsyncSessionFactory() as session:
        result = await session.execute(
            select(Payment).where(Payment.id == payment_id)
        )
        payment = result.scalar_one_or_none()
        if not payment:
            return None
        payment.status = "paid"
        payment.provider_payment_id = provider_payment_id
        payment.paid_at = datetime.utcnow()
        await session.commit()
        return payment


async def expire_subscriptions() -> list[int]:
    """Помечает просроченные подписки — вызывается планировщиком."""
    async with AsyncSessionFactory() as session:
        result = await session.execute(
            select(Subscription).where(
                Subscription.status == "active",
                Subscription.expires_at <= datetime.utcnow(),
            )
        )
        expired = result.scalars().all()
        tg_ids = []
        for sub in expired:
            sub.status = "expired"
            user_result = await session.execute(
                select(User).where(User.id == sub.user_id)
            )
            user = user_result.scalar_one_or_none()
            if user:
                tg_ids.append(user.telegram_id)
        await session.commit()
        return tg_ids


async def get_expiring_soon(days: int = 3) -> list[tuple[int, Subscription]]:
    """Возвращает список (telegram_id, sub) с подписками истекающими через N дней."""
    deadline = datetime.utcnow() + timedelta(days=days)
    async with AsyncSessionFactory() as session:
        result = await session.execute(
            select(User, Subscription)
            .join(Subscription, User.id == Subscription.user_id)
            .where(
                Subscription.status == "active",
                Subscription.expires_at <= deadline,
                Subscription.expires_at > datetime.utcnow(),
            )
        )
        return [(row[0].telegram_id, row[1]) for row in result.all()]
