from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy import select
from datetime import datetime, timedelta

from config import config
from models import Base, Plan

engine = create_async_engine(config.database_url, echo=False)
AsyncSessionFactory = async_sessionmaker(engine, expire_on_commit=False)


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await seed_plans()


async def seed_plans():
    """Создаёт дефолтные тарифы если их нет."""
    async with AsyncSessionFactory() as session:
        result = await session.execute(select(Plan))
        if result.scalars().first():
            return  # уже есть

        plans = [
            Plan(
                name="🥉 Базовый",
                description="1 устройство • Telegram MTProxy • 30 дней",
                price_stars=150,
                price_rub=14900,
                duration_days=30,
                max_devices=1,
                protocols=["mtproxy"],
                sort_order=1,
            ),
            Plan(
                name="🥈 Стандарт",
                description="3 устройства • MTProxy + Xray SOCKS5 • 30 дней",
                price_stars=300,
                price_rub=29900,
                duration_days=30,
                max_devices=3,
                protocols=["mtproxy", "xray"],
                sort_order=2,
            ),
            Plan(
                name="🥇 Премиум",
                description="5 устройств • MTProxy + Xray + WireGuard VPN • 30 дней",
                price_stars=500,
                price_rub=49900,
                duration_days=30,
                max_devices=5,
                protocols=["mtproxy", "xray", "wireguard"],
                sort_order=3,
            ),
        ]
        session.add_all(plans)
        await session.commit()


def get_session() -> AsyncSession:
    return AsyncSessionFactory()
