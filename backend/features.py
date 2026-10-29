"""Growth & support features: coupons, referrals, tab sharing, tickets, notifications, maintenance,
device sessions and batch/scheduled tab actions. Imported at the end of app.py (uses its helpers)."""
import json, re, secrets, time, hashlib
from fastapi import APIRouter, HTTPException, Depends, Request, Body
from pydantic import BaseModel, Field
from sqlalchemy import select, update, delete, func
from .db import *
from .app import (current, admin, tx, lock, audit, uid, now, owned, tab_dict, setting, plans, public_user,
                  restart, SCREEN_IDS, session_token)

router = APIRouter()

REFERRAL_DEFAULTS = {'enabled': True, 'percent': 10, 'max_bonus': 50000, 'referee_bonus': 0}
MAINTENANCE_DEFAULTS = {'enabled': False, 'message': 'Hệ thống đang bảo trì, vui lòng quay lại sau.', 'until': 0}


# ---------- shared helpers (also called from app.py) ----------

def notify(s, user_id, title, body='', link=''):
    s.add(Notification(id=uid(), user_id=user_id, title=title[:120], body=body[:500], link=link[:120]))


def maintenance():
    return {**MAINTENANCE_DEFAULTS, **setting('maintenance', {})}


def ensure_open(u):
    """New rentals/uploads pause during maintenance; admins keep working."""
    m = maintenance()
    if m['enabled'] and u.role != 'admin':
        raise HTTPException(503, m['message'] or MAINTENANCE_DEFAULTS['message'])


def referral():
    return {**REFERRAL_DEFAULTS, **setting('referral', {})}


def ref_code_for(s, user):
    if not user.ref_code:
        while True:
            code = secrets.token_hex(3).upper()
            if not s.scalar(select(User.id).where(User.ref_code == code)): break
        user.ref_code = code
    return user.ref_code


def coupon_quote(s, code, user_id, context, amount):
    """Validate a coupon for 'rent' (discount) or 'topup' (bonus). Returns (coupon, discount_or_bonus)."""
    c = s.get(Coupon, (code or '').strip().upper())
    if not c or not c.active: raise HTTPException(422, 'Mã khuyến mãi không tồn tại.')
    if c.expires and c.expires <= now(): raise HTTPException(422, 'Mã khuyến mãi đã hết hạn.')
    if c.max_uses and c.used >= c.max_uses: raise HTTPException(422, 'Mã khuyến mãi đã hết lượt dùng.')
    if (context == 'topup') != (c.kind == 'topup'):
        raise HTTPException(422, 'Mã này dùng cho nạp tiền.' if c.kind == 'topup' else 'Mã này dùng khi thuê hoặc gia hạn tab.')
    if c.min_amount and amount < c.min_amount: raise HTTPException(422, f'Mã cần đơn tối thiểu {c.min_amount:,}đ.'.replace(',', '.'))
    mine = s.scalar(select(func.count()).select_from(CouponUse).where(CouponUse.code == c.code, CouponUse.user_id == user_id)) or 0
    if c.per_user and mine >= c.per_user: raise HTTPException(422, 'Bạn đã dùng hết lượt của mã này.')
    value = amount * c.value // 100 if c.kind in ('percent', 'topup') else c.value
    if c.max_value: value = min(value, c.max_value)
    return c, min(value, amount) if c.kind != 'topup' else value


def redeem(s, c, user_id, amount, context):
    c.used += 1
    s.add(CouponUse(id=uid(), code=c.code, user_id=user_id, amount=amount, context=context))


def discounted(s, code, user, price, context='rent'):
    """Price after an optional coupon; records the redemption. Returns (price, coupon_code)."""
    if not code: return price, ''
    c, off = coupon_quote(s, code, user.id, context, price)
    redeem(s, c, user.id, off, context)
    return price - off, c.code


def on_payment(s, order, owner):
    """After a top-up is credited: coupon bonus, referral reward, notification."""
    if order.coupon:
        try:
            c, bonus = coupon_quote(s, order.coupon, owner.id, 'topup', order.amount)
            if bonus > 0:
                redeem(s, c, owner.id, bonus, 'topup')
                owner.balance += bonus
                s.add(Ledger(id=uid(), user_id=owner.id, amount=bonus, description=f'Thưởng nạp ({c.code})'))
        except HTTPException:
            pass  # coupon expired between order and payment: the transfer itself still counts
    ref = referral()
    first = (s.scalar(select(func.count()).select_from(Order).where(Order.user_id == owner.id, Order.status == 'paid')) or 0) <= 1
    if ref['enabled'] and owner.referred_by and first:
        inviter = lock(s, User, owner.referred_by)
        reward = min(order.amount * int(ref['percent']) // 100, int(ref['max_bonus']))
        if inviter and not inviter.blocked and reward > 0:
            inviter.balance += reward
            s.add(Ledger(id=uid(), user_id=inviter.id, amount=reward, description=f'Thưởng giới thiệu {owner.name}'[:160]))
            notify(s, inviter.id, 'Bạn nhận thưởng giới thiệu', f'+{reward:,}đ khi {owner.name} nạp tiền lần đầu.'.replace(',', '.'), '/wallet')
        if int(ref['referee_bonus']) > 0:
            owner.balance += int(ref['referee_bonus'])
            s.add(Ledger(id=uid(), user_id=owner.id, amount=int(ref['referee_bonus']), description='Thưởng người mới (mã giới thiệu)'))
    notify(s, owner.id, 'Nạp tiền thành công', f'+{order.amount:,}đ đã vào ví.'.replace(',', '.'), '/wallet')


def daily_target(hhmm, ts):
    """Timestamp of today's HH:MM (server local time) for ts."""
    lt = time.localtime(ts)
    h, m = map(int, hhmm.split(':'))
    return int(time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, h, m, 0, 0, 0, -1)))


def on_heartbeat(s, t, owner):
    """Per-tab housekeeping each heartbeat: scheduled restart and expiry reminder."""
    if t.restart_at and t.desired == 'running' and t.game and t.expires > now():
        target = daily_target(t.restart_at, now())
        if now() >= target > t.last_restart:
            t.boot += 1; t.last_restart = now(); restart(t)
            audit(s, 'system', 'tab.scheduled_restart', t.id)
    hours = json.loads(owner.prefs or '{}').get('expiry_alert_hours', 24) if owner else 24
    if owner and hours and not t.notified_expiry and now() < t.expires < now() + hours * 3600:
        t.notified_expiry = 1
        notify(s, owner.id, f'Tab "{t.name}" sắp hết hạn',
               'Bật tự động gia hạn hoặc gia hạn ngay để game không bị dừng.', f'/tabs/{t.id}')


# ---------- referral ----------

@router.get('/api/me/referral')
def my_referral(u=Depends(current)):
    with tx() as s:
        me = lock(s, User, u.id)
        code = ref_code_for(s, me)
        invited = s.scalars(select(User).where(User.referred_by == u.id)).all()
        earned = s.scalar(select(func.sum(Ledger.amount)).where(Ledger.user_id == u.id, Ledger.description.like('Thưởng giới thiệu%'))) or 0
        ref = referral()
        return {'code': code, 'path': f'/#/register?ref={code}', 'enabled': ref['enabled'], 'percent': ref['percent'],
                'max_bonus': ref['max_bonus'], 'invited': len(invited), 'earned': earned,
                'friends': [{'name': x.name, 'created': x.created} for x in invited[-50:]]}


# ---------- coupons ----------

class CouponCheck(BaseModel):
    code: str = Field(min_length=2, max_length=32)
    context: str = Field(pattern='^(rent|topup)$')
    amount: int = Field(ge=0, le=10_000_000)

@router.post('/api/coupons/check')
def check_coupon(b: CouponCheck, u=Depends(current)):
    # Read-only preview: nothing is redeemed until the rental or top-up happens.
    with Session() as s:
        c, value = coupon_quote(s, b.code, u.id, b.context, b.amount)
        code = c.code
    if b.context == 'topup':
        return {'ok': True, 'code': code, 'bonus': value, 'message': f'Nhận thêm {value:,}đ khi nạp.'.replace(',', '.')}
    return {'ok': True, 'code': code, 'discount': value, 'final': b.amount - value, 'message': f'Giảm {value:,}đ.'.replace(',', '.')}

class CouponIn(BaseModel):
    code: str = Field(pattern=r'^[A-Za-z0-9_-]{3,32}$')
    kind: str = Field(pattern='^(percent|amount|topup)$')
    value: int = Field(ge=1, le=10_000_000)
    max_value: int = Field(default=0, ge=0, le=10_000_000)
    min_amount: int = Field(default=0, ge=0, le=10_000_000)
    max_uses: int = Field(default=0, ge=0, le=1_000_000)
    per_user: int = Field(default=1, ge=0, le=1000)
    expires: int = Field(default=0, ge=0)
    active: bool = True
    note: str = Field(default='', max_length=120)

def coupon_dict(c):
    return {k: getattr(c, k) for k in ('code', 'kind', 'value', 'max_value', 'min_amount', 'max_uses', 'per_user', 'used', 'expires', 'active', 'note', 'created')}

@router.get('/api/admin/coupons')
def list_coupons(u=Depends(admin)):
    with Session() as s:
        return {'coupons': [coupon_dict(c) for c in s.scalars(select(Coupon).order_by(Coupon.created.desc()))],
                'uses': [{'code': x.code, 'user_id': x.user_id, 'amount': x.amount, 'context': x.context, 'created': x.created}
                         for x in s.scalars(select(CouponUse).order_by(CouponUse.created.desc()).limit(200))]}

@router.post('/api/admin/coupons', status_code=201)
def create_coupon(b: CouponIn, u=Depends(admin)):
    if b.kind in ('percent', 'topup') and b.value > 100: raise HTTPException(422, 'Phần trăm tối đa 100.')
    with tx() as s:
        code = b.code.upper()
        if s.get(Coupon, code): raise HTTPException(409, 'Mã đã tồn tại.')
        c = Coupon(**{**b.model_dump(), 'code': code, 'active': int(b.active)})
        s.add(c); audit(s, u.id, 'coupon.create', code); s.flush()
        return coupon_dict(c)

@router.put('/api/admin/coupons/{code}')
def edit_coupon(code: str, b: CouponIn, u=Depends(admin)):
    if b.kind in ('percent', 'topup') and b.value > 100: raise HTTPException(422, 'Phần trăm tối đa 100.')
    with tx() as s:
        c = lock(s, Coupon, code.upper())
        if not c: raise HTTPException(404, 'Không tìm thấy mã.')
        for k, v in b.model_dump().items():
            if k != 'code': setattr(c, k, int(v) if isinstance(v, bool) else v)
        audit(s, u.id, 'coupon.update', c.code)
        return coupon_dict(c)

@router.delete('/api/admin/coupons/{code}')
def delete_coupon(code: str, u=Depends(admin)):
    with tx() as s:
        c = lock(s, Coupon, code.upper())
        if not c: raise HTTPException(404, 'Không tìm thấy mã.')
        s.delete(c); audit(s, u.id, 'coupon.delete', code.upper())
    return {'ok': True}


# ---------- tab sharing ----------

class ShareIn(BaseModel):
    can_control: bool = False
    hours: int = Field(default=24, ge=1, le=720)
    label: str = Field(default='', max_length=40)

def share_dict(x):
    return {'token': x.token, 'label': x.label, 'can_control': bool(x.can_control), 'expires': x.expires, 'created': x.created, 'path': f'/#/s/{x.token}'}

@router.get('/api/tabs/{id}/shares')
def list_shares(id: str, u=Depends(current)):
    with Session() as s:
        owned(s, id, u)
        return [share_dict(x) for x in s.scalars(select(Share).where(Share.tab_id == id, Share.expires > now()).order_by(Share.created.desc()))]

@router.post('/api/tabs/{id}/shares', status_code=201)
def create_share(id: str, b: ShareIn, u=Depends(current)):
    with tx() as s:
        t = owned(s, id, u)
        if s.scalar(select(func.count()).select_from(Share).where(Share.tab_id == id, Share.expires > now())) >= 10:
            raise HTTPException(409, 'Tối đa 10 liên kết chia sẻ cho mỗi tab.')
        x = Share(token=secrets.token_urlsafe(18), tab_id=id, user_id=t.user_id, label=b.label.strip(),
                  can_control=int(b.can_control), expires=min(now() + b.hours * 3600, t.expires))
        s.add(x); audit(s, u.id, 'tab.share', id)
        return share_dict(x)

@router.delete('/api/tabs/{id}/shares/{token}')
def revoke_share(id: str, token: str, u=Depends(current)):
    with tx() as s:
        owned(s, id, u)
        s.execute(delete(Share).where(Share.tab_id == id, Share.token == token)); audit(s, u.id, 'tab.unshare', id)
    return {'ok': True}

def share_lookup(s, token):
    x = s.get(Share, token)
    if not x or x.expires <= now(): return None, None
    t = s.get(Tab, x.tab_id)
    return (x, t) if t and t.expires > now() else (None, None)

@router.get('/api/share/{token}')
def open_share(token: str):
    # Public: anyone with the link sees the tab name, status and screen; no owner details.
    with Session() as s:
        x, t = share_lookup(s, token)
        if not x: raise HTTPException(404, 'Liên kết chia sẻ không tồn tại hoặc đã hết hạn.')
        return {'tab_id': t.id, 'name': t.name, 'status': t.status, 'desired': t.desired, 'screen': t.screen,
                'can_control': bool(x.can_control), 'expires': x.expires, 'label': x.label}


# ---------- support tickets ----------

class TicketIn(BaseModel):
    subject: str = Field(min_length=3, max_length=120)
    body: str = Field(min_length=1, max_length=4000)
class MessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=4000)

def ticket_dict(s, t, with_messages=False):
    d = {k: getattr(t, k) for k in ('id', 'subject', 'status', 'created', 'updated')}
    d['messages_count'] = s.scalar(select(func.count()).select_from(TicketMessage).where(TicketMessage.ticket_id == t.id)) or 0
    if with_messages:
        d['messages'] = [{'id': m.id, 'staff': bool(m.staff), 'body': m.body, 'created': m.created}
                         for m in s.scalars(select(TicketMessage).where(TicketMessage.ticket_id == t.id).order_by(TicketMessage.created))]
    return d

@router.get('/api/tickets')
def my_tickets(u=Depends(current)):
    with Session() as s:
        return [ticket_dict(s, t) for t in s.scalars(select(Ticket).where(Ticket.user_id == u.id).order_by(Ticket.updated.desc()))]

@router.post('/api/tickets', status_code=201)
def open_ticket(b: TicketIn, u=Depends(current)):
    from .app import limit
    limit('ticket:' + u.id, 10, 3600)
    with tx() as s:
        t = Ticket(id=uid(), user_id=u.id, subject=b.subject.strip())
        s.add(t); s.add(TicketMessage(id=uid(), ticket_id=t.id, author_id=u.id, body=b.body.strip()))
        audit(s, u.id, 'ticket.open', t.id); s.flush()
        return ticket_dict(s, t, True)

def own_ticket(s, id, u):
    t = lock(s, Ticket, id)
    if not t or (t.user_id != u.id and u.role != 'admin'): raise HTTPException(404, 'Không tìm thấy yêu cầu hỗ trợ.')
    return t

@router.get('/api/tickets/{id}')
def get_ticket(id: str, u=Depends(current)):
    with tx() as s: return ticket_dict(s, own_ticket(s, id, u), True)

@router.post('/api/tickets/{id}/messages')
def reply_ticket(id: str, b: MessageIn, u=Depends(current)):
    from .app import limit
    limit('ticket-msg:' + u.id, 60, 3600)
    with tx() as s:
        t = own_ticket(s, id, u)
        staff = u.role == 'admin' and t.user_id != u.id
        s.add(TicketMessage(id=uid(), ticket_id=id, author_id=u.id, staff=int(staff), body=b.body.strip()))
        t.status = 'answered' if staff else 'open'; t.updated = now()
        if staff: notify(s, t.user_id, 'Hỗ trợ đã trả lời', t.subject, f'/support/{t.id}')
        return ticket_dict(s, t, True)

@router.post('/api/tickets/{id}/close')
def close_ticket(id: str, u=Depends(current)):
    with tx() as s:
        t = own_ticket(s, id, u); t.status = 'closed'; t.updated = now()
        return ticket_dict(s, t, True)

@router.get('/api/admin/tickets')
def admin_tickets(status: str = '', u=Depends(admin)):
    with Session() as s:
        q = select(Ticket).order_by(Ticket.updated.desc()).limit(300)
        if status: q = q.where(Ticket.status == status)
        users = {x.id: x for x in s.scalars(select(User))}
        return [{**ticket_dict(s, t), 'user_id': t.user_id, 'email': getattr(users.get(t.user_id), 'email', '')} for t in s.scalars(q)]


# ---------- notifications ----------

@router.get('/api/notifications')
def my_notifications(u=Depends(current)):
    with Session() as s:
        items = s.scalars(select(Notification).where(Notification.user_id == u.id).order_by(Notification.created.desc()).limit(50)).all()
        unread = s.scalar(select(func.count()).select_from(Notification).where(Notification.user_id == u.id, Notification.read == 0)) or 0
        return {'unread': unread, 'items': [{k: getattr(n, k) for k in ('id', 'title', 'body', 'link', 'read', 'created')} for n in items]}

class ReadIn(BaseModel):
    ids: list[str] = Field(default_factory=list, max_length=200)
    all: bool = False

@router.post('/api/notifications/read')
def read_notifications(b: ReadIn, u=Depends(current)):
    with tx() as s:
        q = update(Notification).where(Notification.user_id == u.id)
        if not b.all: q = q.where(Notification.id.in_(b.ids))
        s.execute(q.values(read=1))
    return {'ok': True}

class Broadcast(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(default='', max_length=500)
    link: str = Field(default='', max_length=120)
    user_id: str | None = None

@router.post('/api/admin/notifications')
def broadcast(b: Broadcast, u=Depends(admin)):
    with tx() as s:
        ids = [b.user_id] if b.user_id else list(s.scalars(select(User.id).where(User.blocked == 0)))
        for i in ids: notify(s, i, b.title, b.body, b.link)
        audit(s, u.id, 'notify.broadcast', str(len(ids)))
    return {'ok': True, 'sent': len(ids)}


# ---------- device sessions ----------

@router.get('/api/me/sessions')
def my_sessions(req: Request, u=Depends(current)):
    mine = hashlib.sha256(session_token(req).encode()).hexdigest()
    with Session() as s:
        rows = s.scalars(select(AuthSession).where(AuthSession.user_id == u.id, AuthSession.expires > now()).order_by(AuthSession.created.desc()))
        return [{'id': x.hash[:16], 'agent': x.agent, 'created': x.created, 'expires': x.expires, 'current': x.hash == mine} for x in rows]

@router.delete('/api/me/sessions/{sid}')
def end_session(sid: str, u=Depends(current)):
    if not re.fullmatch('[0-9a-f]{16}', sid): raise HTTPException(422, 'Phiên không hợp lệ.')
    with tx() as s:
        n = s.execute(delete(AuthSession).where(AuthSession.user_id == u.id, AuthSession.hash.like(sid + '%'))).rowcount
    if not n: raise HTTPException(404, 'Không tìm thấy phiên đăng nhập.')
    return {'ok': True}


# ---------- tab actions: restart, batch, groups, schedule ----------

@router.post('/api/tabs/{id}/restart')
def restart_tab(id: str, u=Depends(current)):
    with tx() as s:
        t = owned(s, id, u)
        if t.expires <= now() or not t.game: raise HTTPException(409, 'Tab chưa có game hoặc đã hết hạn.')
        t.boot += 1; t.desired = 'running'; restart(t); audit(s, u.id, 'tab.restart', id)
        return tab_dict(t)

class Batch(BaseModel):
    ids: list[str] = Field(min_length=1, max_length=50)
    action: str = Field(pattern='^(start|stop|restart|group)$')
    group: str = Field(default='', max_length=40)

@router.post('/api/tabs/batch')
def batch_tabs(b: Batch, u=Depends(current)):
    done = 0
    with tx() as s:
        for id in dict.fromkeys(b.ids):
            t = s.get(Tab, id)
            if not t or (t.user_id != u.id and u.role != 'admin') or t.expires <= now(): continue
            if b.action == 'group': t.group = b.group.strip()
            elif b.action == 'stop': t.desired = 'stopped'
            elif not t.game: continue
            elif b.action == 'start': t.desired = 'running'
            else: t.boot += 1; t.desired = 'running'; restart(t)
            done += 1
        audit(s, u.id, 'tab.batch_' + b.action, str(done))
    return {'ok': True, 'done': done}

class Schedule(BaseModel):
    group: str | None = Field(default=None, max_length=40)
    restart_at: str | None = Field(default=None, pattern=r'^(|([01]\d|2[0-3]):[0-5]\d)$')

@router.patch('/api/tabs/{id}/schedule')
def schedule_tab(id: str, b: Schedule, u=Depends(current)):
    with tx() as s:
        t = owned(s, id, u)
        if b.group is not None: t.group = b.group.strip()
        if b.restart_at is not None:
            t.restart_at = b.restart_at
            # Don't fire immediately for a time that already passed today.
            t.last_restart = now() if b.restart_at and now() >= daily_target(b.restart_at, now()) else t.last_restart
        audit(s, u.id, 'tab.schedule', id)
        return tab_dict(t)


# ---------- admin: settings for referral & maintenance ----------

class ReferralIn(BaseModel):
    enabled: bool = True
    percent: int = Field(ge=0, le=50)
    max_bonus: int = Field(ge=0, le=5_000_000)
    referee_bonus: int = Field(default=0, ge=0, le=1_000_000)
class MaintenanceIn(BaseModel):
    enabled: bool = False
    message: str = Field(default='', max_length=300)
    until: int = Field(default=0, ge=0)

@router.get('/api/admin/growth')
def growth(u=Depends(admin)):
    with Session() as s:
        top = s.execute(select(User.referred_by, func.count()).where(User.referred_by != '').group_by(User.referred_by).order_by(func.count().desc()).limit(20)).all()
        names = {x.id: x for x in s.scalars(select(User).where(User.id.in_([r[0] for r in top])))} if top else {}
        return {'referral': referral(), 'maintenance': maintenance(),
                'top_referrers': [{'user_id': r[0], 'email': getattr(names.get(r[0]), 'email', ''), 'invited': r[1]} for r in top],
                'open_tickets': s.scalar(select(func.count()).select_from(Ticket).where(Ticket.status == 'open')) or 0}
