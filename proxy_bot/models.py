from datetime import datetime
from sqlalchemy import (
    BigInteger, Boolean, DateTime, ForeignKey,
    Integer, JSON, String, Text, func
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    telegram_id: Mapped[int] = mapped_column(BigInteger, unique=True, index=True)
    username: Mapped[str | None] = mapped_column(String(64))
    full_name: Mapped[str | None] = mapped_column(String(128))
    lang: Mapped[str] = mapped_column(String(8), default="ru")
    is_banned: Mapped[bool] = mapped_column(Boolean, default=False)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    last_seen: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    subscriptions: Mapped[list["Subscription"]] = relationship(back_populates="user")
    payments: Mapped[list["Payment"]] = relationship(back_populates="user")


class Plan(Base):
    __tablename__ = "plans"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64))            # Базовый / Стандарт / Премиум
    description: Mapped[str | None] = mapped_column(Text)
    price_stars: Mapped[int] = mapped_column(Integer)        # Telegram Stars
    price_rub: Mapped[int] = mapped_column(Integer)          # рубли (копейки)
    duration_days: Mapped[int] = mapped_column(Integer)      # 30 / 90 / 365
    max_devices: Mapped[int] = mapped_column(Integer, default=1)
    protocols: Mapped[list] = mapped_column(JSON, default=list)  # ["mtproxy", "xray", "wireguard"]
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    subscriptions: Mapped[list["Subscription"]] = relationship(back_populates="plan")


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), index=True)
    plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("plans.id"))
    # active | expired | paused | cancelled
    status: Mapped[str] = mapped_column(String(20), default="active", index=True)
    started_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    renewed_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="subscriptions")
    plan: Mapped["Plan"] = relationship(back_populates="subscriptions")
    proxies: Mapped[list["Proxy"]] = relationship(back_populates="subscription", cascade="all, delete-orphan")
    payments: Mapped[list["Payment"]] = relationship(back_populates="subscription")

    @property
    def is_active(self) -> bool:
        return self.status == "active" and self.expires_at > datetime.utcnow()

    @property
    def days_left(self) -> int:
        if self.expires_at < datetime.utcnow():
            return 0
        return (self.expires_at - datetime.utcnow()).days


class Proxy(Base):
    __tablename__ = "proxies"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    subscription_id: Mapped[int] = mapped_column(Integer, ForeignKey("subscriptions.id"), index=True)
    # mtproxy | xray | wireguard
    proxy_type: Mapped[str] = mapped_column(String(20))
    container_name: Mapped[str | None] = mapped_column(String(64))   # имя docker контейнера
    client_name: Mapped[str | None] = mapped_column(String(64))      # имя клиента в mtproxy
    port: Mapped[int | None] = mapped_column(Integer)
    secret: Mapped[str | None] = mapped_column(Text)                 # MTProxy secret
    config_data: Mapped[dict | None] = mapped_column(JSON)           # полный конфиг (WG, Xray)
    tg_link: Mapped[str | None] = mapped_column(Text)                # tg://proxy?...
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    subscription: Mapped["Subscription"] = relationship(back_populates="proxies")


class Payment(Base):
    __tablename__ = "payments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), index=True)
    subscription_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("subscriptions.id"))
    plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("plans.id"))
    amount: Mapped[int] = mapped_column(Integer)          # в копейках или Stars
    currency: Mapped[str] = mapped_column(String(10))     # RUB | XTR (Stars) | USDT
    # stars | cryptobot | yukassa
    provider: Mapped[str] = mapped_column(String(20))
    provider_payment_id: Mapped[str | None] = mapped_column(String(128))  # ID в платёжной системе
    # pending | paid | failed | refunded
    status: Mapped[str] = mapped_column(String(20), default="pending")
    payload: Mapped[dict | None] = mapped_column(JSON)    # доп данные от провайдера
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    paid_at: Mapped[datetime | None] = mapped_column(DateTime)

    user: Mapped["User"] = relationship(back_populates="payments")
    subscription: Mapped["Subscription"] = relationship(back_populates="payments")
