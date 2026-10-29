import os, time
from sqlalchemy import create_engine, event, String, Integer, Text, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

URL = os.getenv('DATABASE_URL', 'sqlite:///./data/thuetab.db')
os.makedirs('data', exist_ok=True)
engine = create_engine(URL, connect_args={'check_same_thread': False, 'timeout': 30} if URL.startswith('sqlite') else {}, pool_pre_ping=True)
if URL.startswith('sqlite'):
    @event.listens_for(engine, 'connect')
    def sqlite_config(connection, _):
        connection.execute('PRAGMA journal_mode=WAL')
        connection.execute('PRAGMA foreign_keys=ON')
Session = sessionmaker(engine, expire_on_commit=False)
class Base(DeclarativeBase): pass
class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password: Mapped[str] = mapped_column(Text)
    name: Mapped[str] = mapped_column(String(60))
    role: Mapped[str] = mapped_column(String(10), default='user')
    balance: Mapped[int] = mapped_column(Integer, default=0)
    blocked: Mapped[int] = mapped_column(Integer, default=0)
    trial_approved: Mapped[int] = mapped_column(Integer, default=0)
    trial_used: Mapped[int] = mapped_column(Integer, default=0)
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
    prefs: Mapped[str] = mapped_column(Text, default='{}')
    max_tabs: Mapped[int] = mapped_column(Integer, default=20)
    last_login: Mapped[int] = mapped_column(Integer, default=0)
    note: Mapped[str] = mapped_column(String(300), default='')
    ref_code: Mapped[str] = mapped_column(String(12), default='')
    referred_by: Mapped[str] = mapped_column(String(32), default='')
class AuthSession(Base):
    __tablename__ = 'sessions'
    hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    expires: Mapped[int] = mapped_column(Integer)
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
    agent: Mapped[str] = mapped_column(String(160), default='')
class Worker(Base):
    __tablename__ = 'workers'
    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    capacity: Mapped[int] = mapped_column(Integer, default=4)
    last_seen: Mapped[int] = mapped_column(Integer, default=0)
    draining: Mapped[int] = mapped_column(Integer, default=0)
    memory_mb: Mapped[int] = mapped_column(Integer, default=0)
class Tab(Base):
    __tablename__ = 'tabs'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    worker_id: Mapped[str] = mapped_column(String(40), index=True)
    slot_id: Mapped[str | None] = mapped_column(String(32), unique=True, nullable=True)
    custom_jar_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    auto_renew: Mapped[int] = mapped_column(Integer, default=0)
    screen: Mapped[str] = mapped_column(String(12), default='240x320')
    group: Mapped[str] = mapped_column(String(40), default='')
    boot: Mapped[int] = mapped_column(Integer, default=0)
    restart_at: Mapped[str] = mapped_column(String(5), default='')
    last_restart: Mapped[int] = mapped_column(Integer, default=0)
    notified_expiry: Mapped[int] = mapped_column(Integer, default=0)
    name: Mapped[str] = mapped_column(String(60))
    game: Mapped[str] = mapped_column(String(40))
    plan: Mapped[str] = mapped_column(String(20))
    desired: Mapped[str] = mapped_column(String(12), default='running')
    status: Mapped[str] = mapped_column(String(12), default='queued')
    error: Mapped[str] = mapped_column(String(200), default='')
    expires: Mapped[int] = mapped_column(Integer)
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))

class CustomJar(Base):
    __tablename__ = 'custom_jars'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    filename: Mapped[str] = mapped_column(String(120))
    file_size: Mapped[int] = mapped_column(Integer, default=0)
    sha256: Mapped[str] = mapped_column(String(64), default='')
    status: Mapped[str] = mapped_column(String(12), default='pending')
    kind: Mapped[str] = mapped_column(String(8), default='jar')
    midlet: Mapped[str] = mapped_column(String(160), default='')
    screen: Mapped[str] = mapped_column(String(12), default='240x320')
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
class Order(Base):
    __tablename__ = 'orders'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    code: Mapped[str] = mapped_column(String(32), unique=True)
    amount: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(20), default='pending')
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
    coupon: Mapped[str] = mapped_column(String(32), default='')
class Payment(Base):
    __tablename__ = 'payments'
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    reference: Mapped[str] = mapped_column(String(160), unique=True)
    order_id: Mapped[str] = mapped_column(String(32), unique=True)
    amount: Mapped[int] = mapped_column(Integer)
class Ledger(Base):
    __tablename__ = 'ledger'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    amount: Mapped[int] = mapped_column(Integer)
    description: Mapped[str] = mapped_column(String(160))
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
class Audit(Base):
    __tablename__ = 'audit'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    actor: Mapped[str] = mapped_column(String(32))
    action: Mapped[str] = mapped_column(String(80))
    target: Mapped[str] = mapped_column(String(80))
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
class Rate(Base):
    __tablename__ = 'rate_limits'
    key: Mapped[str] = mapped_column(String(160), primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)
    reset: Mapped[int] = mapped_column(Integer)
class Command(Base):
    __tablename__ = 'commands'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    tab_id: Mapped[str] = mapped_column(String(32), index=True)
    key: Mapped[str] = mapped_column(String(16), default='')
    text: Mapped[str] = mapped_column(String(64), default='')
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))

class Slot(Base):
    __tablename__ = 'slots'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    worker_id: Mapped[str] = mapped_column(String(40), index=True)
    plan: Mapped[str] = mapped_column(String(20))
    expires: Mapped[int] = mapped_column(Integer)
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))

class Setting(Base):
    __tablename__ = 'settings'
    key: Mapped[str] = mapped_column(String(40), primary_key=True)
    value: Mapped[str] = mapped_column(Text)

class Coupon(Base):
    __tablename__ = 'coupons'
    code: Mapped[str] = mapped_column(String(32), primary_key=True)
    kind: Mapped[str] = mapped_column(String(10))          # percent | amount (rentals) | topup (bonus %)
    value: Mapped[int] = mapped_column(Integer)
    max_value: Mapped[int] = mapped_column(Integer, default=0)   # cap for percent/topup, 0 = none
    min_amount: Mapped[int] = mapped_column(Integer, default=0)
    max_uses: Mapped[int] = mapped_column(Integer, default=0)    # 0 = unlimited
    per_user: Mapped[int] = mapped_column(Integer, default=1)
    used: Mapped[int] = mapped_column(Integer, default=0)
    expires: Mapped[int] = mapped_column(Integer, default=0)     # 0 = never
    active: Mapped[int] = mapped_column(Integer, default=1)
    note: Mapped[str] = mapped_column(String(120), default='')
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
class CouponUse(Base):
    __tablename__ = 'coupon_uses'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    code: Mapped[str] = mapped_column(String(32), index=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    amount: Mapped[int] = mapped_column(Integer)
    context: Mapped[str] = mapped_column(String(20))
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
class Share(Base):
    __tablename__ = 'shares'
    token: Mapped[str] = mapped_column(String(40), primary_key=True)
    tab_id: Mapped[str] = mapped_column(String(32), index=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    label: Mapped[str] = mapped_column(String(40), default='')
    can_control: Mapped[int] = mapped_column(Integer, default=0)
    expires: Mapped[int] = mapped_column(Integer)
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
class Ticket(Base):
    __tablename__ = 'tickets'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    subject: Mapped[str] = mapped_column(String(120))
    status: Mapped[str] = mapped_column(String(12), default='open')   # open | answered | closed
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
    updated: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
class TicketMessage(Base):
    __tablename__ = 'ticket_messages'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    ticket_id: Mapped[str] = mapped_column(String(32), index=True)
    author_id: Mapped[str] = mapped_column(String(32))
    staff: Mapped[int] = mapped_column(Integer, default=0)
    body: Mapped[str] = mapped_column(Text)
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
class Notification(Base):
    __tablename__ = 'notifications'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    title: Mapped[str] = mapped_column(String(120))
    body: Mapped[str] = mapped_column(String(500), default='')
    link: Mapped[str] = mapped_column(String(120), default='')
    read: Mapped[int] = mapped_column(Integer, default=0)
    created: Mapped[int] = mapped_column(Integer, default=lambda:int(time.time()))
