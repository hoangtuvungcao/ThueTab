import os, json, time, secrets, hashlib, re, hmac, io, zipfile, asyncio, ipaddress
from pathlib import Path
from contextlib import asynccontextmanager, contextmanager
from urllib.parse import urlencode
from fastapi import FastAPI, Request, Response, HTTPException, Depends, WebSocket, WebSocketDisconnect, Body
from starlette.concurrency import run_in_threadpool
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from sqlalchemy import select, update, delete, func, text, inspect
from sqlalchemy.exc import IntegrityError
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, InvalidHashError
from PIL import Image
from .db import *
from .stream import hub, Viewer, FPS_CHOICES

ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT/'backend/catalog.json').read_text())
DEFAULT_PLANS = [
    {'id':'day','name':'Linh hoạt 1 Ngày','days':1,'price':int(os.getenv('PRICE_DAY','1500'))},
    {'id':'week','name':'Khởi động 7 Ngày','days':7,'price':int(os.getenv('PRICE_WEEK','8000'))},
    {'id':'month','name':'Chiến binh 30 Ngày','days':30,'price':int(os.getenv('PRICE_MONTH','9000'))},
    {'id':'combo3m','name':'Siêu VIP 90 Ngày','days':90,'price':int(os.getenv('PRICE_COMBO3M','24000'))}
]
WORKER_TOKEN = os.getenv('WORKER_TOKEN','')
SECURE = os.getenv('COOKIE_SECURE','false').lower() == 'true'
# Web front-end origin(s), comma-separated. The front-end may live on another host (e.g. Cloudflare Pages)
# than this API; cookies and WebSockets are only accepted from these origins.
ORIGINS = [o.strip().rstrip('/') for o in os.getenv('PUBLIC_ORIGIN','http://127.0.0.1:8000').split(',') if o.strip()]
ORIGIN = ORIGINS[0]
DEV_ORIGINS = ('http://127.0.0.1:5173','http://localhost:5173')
TRIAL_MINUTES = int(os.getenv('TRIAL_MINUTES','60'))
VERSION = '1.1.0'
SESSION_SECONDS = 14*86400
# Uploaded JARs run in the same locked-down container as catalog games; set false to require admin review.
JAR_AUTO_APPROVE = os.getenv('JAR_AUTO_APPROVE','true').lower() == 'true'
SUPPORT_KEYS = ('zalo','telegram','facebook','email','hotline')
SUPPORT = {k:os.getenv('SUPPORT_'+k.upper(),'') for k in SUPPORT_KEYS}
# Editable by admins at /api/admin/settings; these are the defaults until saved.
SITE_DEFAULTS = {
    'announcement': '',
    'hero_title': 'Treo game Java 24/24 trên đám mây',
    'hero_subtitle': 'Tải lên file .jar game J2ME hoặc Java PC. Xem màn hình, chạm, bấm phím từ điện thoại hoặc máy tính, đổi game bất cứ lúc nào.',
    'cta': 'Bắt đầu ngay',
    'features': [
        {'title':'Chạy 24/24','text':'Tắt máy, tắt trình duyệt — game vẫn chạy đến khi hết hạn.'},
        {'title':'Mượt 30/60 FPS','text':'Màn hình truyền trực tiếp, phím và chạm phản hồi tức thì.'},
        {'title':'Màn dọc hoặc ngang','text':'Đổi kích thước màn hình game theo ý bạn, kể cả HD.'},
        {'title':'Nhiều tab cùng lúc','text':'Xem nhiều màn hình và điều khiển đồng bộ bằng một bàn phím.'},
    ],
    'steps': [
        {'title':'Nạp tiền','text':'Chuyển khoản theo mã QR, tiền tự vào ví.'},
        {'title':'Thuê tab & tải game','text':'Chọn gói, tải file .jar của bạn lên.'},
        {'title':'Chơi mọi nơi','text':'Mở trên web hoặc ứng dụng, điều khiển từ xa.'},
    ],
    'faq': [
        {'q':'Tắt máy thì game có dừng không?','a':'Không. Game chạy trên máy chủ đến khi tab hết hạn hoặc bạn bấm dừng.'},
        {'q':'Chạy được game nào?','a':'Game J2ME (.jar) và game Java PC có Main-Class. Bạn tự tải file .jar hợp lệ của mình.'},
        {'q':'Đổi game hoặc xoay màn hình được không?','a':'Được, bất cứ lúc nào. Tab khởi động lại với game hoặc kích thước mới, thời hạn giữ nguyên.'},
        {'q':'Nạp tiền bao lâu thì vào ví?','a':'Thường 5–30 giây sau khi chuyển khoản đúng nội dung.'},
    ],
    'footer': 'ThuêTab — treo game Java 24/24.',
}
DOWNLOAD_DIR_NAME = 'downloads'
# App builds an operator drops into data/downloads/, matched by file name.
# Matched by file-name ending: the Windows and macOS builds are both .zip archives.
DOWNLOAD_PLATFORMS = [
    ('windows','Windows',('.exe','.msi','Windows.zip')),('android','Android',('.apk',)),
    ('linux','Linux',('.x86_64','.AppImage','.tar.gz')),('macos','macOS',('.dmg','macOS.zip')),
]  # iOS: the web app installed to the home screen (PWA), no native build
ph = PasswordHasher()
uid = lambda: secrets.token_hex(12)
now = lambda: int(time.time())
# DATA_DIR lets tests use a throwaway directory instead of the real uploads.
DATA_DIR = Path(os.getenv('DATA_DIR', ROOT/'data'))
FRAME_DIR = DATA_DIR/'frames'
FRAME_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR = DATA_DIR/'logs'
LOG_DIR.mkdir(parents=True, exist_ok=True)
JAR_DIR = DATA_DIR/'jars'
JAR_DIR.mkdir(parents=True, exist_ok=True)

@contextmanager
def tx():
    with Session() as s:
        try:
            if engine.dialect.name == 'sqlite': s.execute(text('BEGIN IMMEDIATE'))
            yield s
            s.commit()
        except Exception:
            s.rollback()
            raise

def lock(s, model, ident):
    return s.scalar(select(model).where(model.__table__.primary_key.columns.values()[0] == ident).with_for_update())

def audit(s, actor, action, target): s.add(Audit(id=uid(), actor=actor, action=action, target=target))
def public_user(u): return {**{k:getattr(u,k) for k in ('id','email','name','role','balance','blocked','trial_approved','trial_used','created','max_tabs')},'prefs':{**PREF_DEFAULTS,**json.loads(u.prefs or '{}')}}

# Per-user preferences, synced between web and app. Each key lists its allowed values (or a type).
PREF_DEFAULTS={'theme':'dark','accent':'neon','font_scale':100,'density':'comfortable','reduce_motion':False,
               'default_fps':30,'show_fps':True,'keypad_size':'md','haptics':True,'sounds':False,
               'default_screen':'240x320','start_page':'tabs','wall_columns':'auto','expiry_alert_hours':24}
PREF_CHOICES={'theme':{'dark','light','system'},'accent':{'neon','violet','emerald','amber','rose'},'font_scale':{90,100,110,125},
              'density':{'comfortable','compact'},'reduce_motion':bool,'default_fps':{30,60},'show_fps':bool,'keypad_size':{'sm','md','lg'},
              'haptics':bool,'sounds':bool,'default_screen':None,'start_page':{'tabs','wall','jars','wallet','plans','help','account','download'},
              'wall_columns':{'auto',2,3,4},'expiry_alert_hours':{0,6,12,24,48}}

def setting(key,default):
    with Session() as s:
        row=s.get(Setting,key)
        return json.loads(row.value) if row else default

def plans():
    return [p for p in setting('plans',DEFAULT_PLANS) if p.get('active',True)]

def downloads():
    folder=DATA_DIR/DOWNLOAD_DIR_NAME
    out=[]
    for pid,label,exts in DOWNLOAD_PLATFORMS:
        files=sorted((f for f in folder.glob('*') if f.is_file() and f.name.endswith(exts)),key=lambda f:f.stat().st_mtime,reverse=True) if folder.is_dir() else []
        if files: out.append({'platform':pid,'label':label,'file':files[0].name,'size':files[0].stat().st_size,'updated':int(files[0].stat().st_mtime),'url':'/api/downloads/'+files[0].name})
    # Platforms without a local build link to the latest GitHub release (served by GitHub's CDN, no server bandwidth).
    have={d['platform'] for d in out}
    for asset in release_assets():
        pid=next((pid for pid,_,exts in DOWNLOAD_PLATFORMS if asset['name'].endswith(exts)),None)
        if pid and pid not in have:
            have.add(pid)
            out.append({'platform':pid,'label':dict((x[0],x[1]) for x in DOWNLOAD_PLATFORMS)[pid],'file':asset['name'],
                        'size':asset['size'],'updated':asset['updated'],'url':asset['url']})
    return out

APP_RELEASE_REPO=os.getenv('APP_RELEASE_REPO','')
_release_cache={'at':0,'assets':[]}
def release_assets():
    """Assets of the latest GitHub release of APP_RELEASE_REPO, cached for an hour (empty if unset/unreachable)."""
    if not APP_RELEASE_REPO: return []
    if time.time()-_release_cache['at']<3600: return _release_cache['assets']
    _release_cache['at']=time.time()
    try:
        import httpx, datetime
        r=httpx.get(f'https://api.github.com/repos/{APP_RELEASE_REPO}/releases/latest',timeout=4,headers={'Accept':'application/vnd.github+json'})
        r.raise_for_status()
        ts=lambda v: int(datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()) if v else 0
        _release_cache['assets']=[{'name':a['name'],'size':a['size'],'updated':ts(a.get('updated_at')),'url':a['browser_download_url']}
                                  for a in r.json().get('assets',[])]
    except Exception:
        _release_cache['at']=time.time()-3300  # retry in ~5 minutes
    return _release_cache['assets']
def jar_dict(j): return {k:getattr(j,k) for k in ('id','filename','file_size','sha256','status','kind','midlet','screen','created')}

def superclass(data):
    """Return (class, superclass) names from a .class file by walking its constant pool."""
    import struct
    if data[:4]!=b'\xca\xfe\xba\xbe': return None
    count=struct.unpack('>H',data[8:10])[0];pos=10;utf8={};classes={};i=1
    sizes={3:4,4:4,5:8,6:8,8:2,9:4,10:4,11:4,12:4,15:3,16:2,17:4,18:4,19:2,20:2}
    while i<count:
        tag=data[pos]
        if tag==1:
            n=struct.unpack('>H',data[pos+1:pos+3])[0];utf8[i]=data[pos+3:pos+3+n].decode('utf-8','replace');pos+=3+n
        elif tag==7: classes[i]=struct.unpack('>H',data[pos+1:pos+3])[0];pos+=3
        elif tag in sizes: pos+=1+sizes[tag]
        else: return None
        i+=2 if tag in (5,6) else 1
    this,sup=struct.unpack('>HH',data[pos+2:pos+6])
    return utf8.get(classes.get(this)),utf8.get(classes.get(sup))

def find_midlet(z):
    # JARs shipped with a separate .jad have no manifest; find the class extending MIDlet instead.
    found=[]
    for info in z.infolist()[:5000]:
        if info.filename.endswith('.class') and info.file_size<2_000_000:
            names=superclass(z.read(info))
            if names and names[1]=='javax/microedition/midlet/MIDlet': found.append(names[0].replace('/','.'))
    return found[0] if len(found)==1 else None

def inspect_jar(content):
    # Returns (kind, midlet_class, screen hint): 'midp' for J2ME MIDlets, 'jar' for desktop Java with Main-Class.
    try:
        with zipfile.ZipFile(io.BytesIO(content)) as z:
            try:
                info=z.getinfo('META-INF/MANIFEST.MF')
                if info.file_size>65536: raise ValueError
                manifest=z.read(info).decode('utf-8','replace').replace('\r\n ','').replace('\n ','')
            except KeyError: manifest=''
            midlet=None if 'MIDlet-1' in manifest or 'Main-Class' in manifest else find_midlet(z)
    except (zipfile.BadZipFile,ValueError,Exception) as e:
        if isinstance(e,HTTPException): raise
        raise HTTPException(422,'File JAR bị hỏng, không đọc được.')
    if midlet: return 'midp',midlet,'240x320'
    fields={k.strip().lower():v.strip() for k,_,v in (l.partition(':') for l in manifest.splitlines()) if _}
    if 'midlet-1' in fields:
        cls=fields['midlet-1'].split(',')[-1].strip()
        if re.fullmatch(r'[A-Za-z_$][\w$.]{0,150}',cls): return 'midp',cls,screen_hint(fields)
    if re.fullmatch(r'[A-Za-z_$][\w$.]{0,150}',fields.get('main-class','')): return 'jar','','640x480'
    raise HTTPException(422,'JAR không có MIDlet-1 (game J2ME) hoặc Main-Class (Java PC).')
def live_payment(): return bool(os.getenv('SEPAY_API_KEY') and os.getenv('BANK_ACCOUNT'))
TAB_FIELDS=('id','name','game','plan','desired','status','error','expires','created','slot_id','custom_jar_id','auto_renew','screen','group','restart_at','boot')
# Emulated J2ME screen sizes a tab can switch between (game restarts on change).
SCREENS=[{'id':'240x320','label':'Dọc 240×320','orientation':'portrait'},{'id':'320x240','label':'Ngang 320×240','orientation':'landscape'},
         {'id':'360x640','label':'Dọc HD 360×640','orientation':'portrait'},{'id':'640x360','label':'Ngang HD 640×360','orientation':'landscape'},
         {'id':'176x220','label':'Dọc nhỏ 176×220','orientation':'portrait'}]
SCREEN_IDS={x['id'] for x in SCREENS}
def screen_hint(fields):
    # Some JADs/manifests declare their intended size, e.g. "Nokia-MIDlet-Original-Display-Size: 320,240".
    for key in ('nokia-midlet-original-display-size','midlet-screen-size','nokia-midlet-target-display-size'):
        m=re.fullmatch(r'\s*(\d+)\s*[,x×]\s*(\d+)\s*',fields.get(key,''))
        if m and f'{m[1]}x{m[2]}' in SCREEN_IDS: return f'{m[1]}x{m[2]}'
    return '240x320'
def tab_dict(t): return {k:getattr(t,k) for k in TAB_FIELDS}
def internal_tab(t): return {**tab_dict(t),'worker_id':t.worker_id,'user_id':t.user_id}
def limit(key, cap, seconds):
    # DB-wide gate; PostgreSQL advisory lock serializes first insertion across processes.
    with tx() as s:
        if engine.dialect.name == 'postgresql': s.execute(text('SELECT pg_advisory_xact_lock(:k)'), {'k':int.from_bytes(hashlib.sha256(key.encode()).digest()[:8], 'big', signed=True)})
        r=lock(s,Rate,key)
        if r is None: s.add(Rate(key=key,count=1,reset=now()+seconds))
        elif r.reset <= now(): r.count=1; r.reset=now()+seconds
        elif r.count >= cap: raise HTTPException(429,'Thao tác quá nhanh. Vui lòng thử lại sau.')
        else: r.count+=1

# Reverse proxies on these networks (Caddy, cloudflared, Docker's gateway) may report the visitor's IP.
TRUSTED_PROXIES=[ipaddress.ip_network(x.strip()) for x in os.getenv('TRUSTED_PROXIES','127.0.0.1/32,::1/128,172.16.0.0/12').split(',') if x.strip()]
def client_ip(req):
    """Visitor IP for rate limits. Forwarded headers count only when the direct peer is a trusted proxy,
    otherwise anyone could spoof them; behind a proxy every visitor would otherwise share one IP."""
    peer=req.client.host if req.client else ''
    try: trusted=any(ipaddress.ip_address(peer) in n for n in TRUSTED_PROXIES)
    except ValueError: trusted=False
    if trusted:
        fwd=req.headers.get('cf-connecting-ip') or req.headers.get('x-forwarded-for','').split(',')[0]
        try: return str(ipaddress.ip_address(fwd.strip()))
        except ValueError: pass
    return peer
def session_token(req):
    auth=req.headers.get('authorization','')
    return auth[7:] if auth.startswith('Bearer ') else req.cookies.get('tt_session','')
def user_for(token):
    with Session() as s:
        session=s.get(AuthSession, hashlib.sha256(token.encode()).hexdigest())
        if not session or session.expires<now(): return None
        u=s.get(User,session.user_id)
        return u if u and not u.blocked else None
def current(req:Request):
    token=session_token(req)
    with Session() as s:
        session=s.get(AuthSession, hashlib.sha256(token.encode()).hexdigest())
        if not session or session.expires<now(): raise HTTPException(401,'Vui lòng đăng nhập.')
        u=s.get(User,session.user_id)
        if not u or u.blocked: raise HTTPException(403,'Tài khoản đã bị khóa.')
        return u

def admin(u=Depends(current)):
    if u.role!='admin': raise HTTPException(403,'Bạn không có quyền quản trị.')
    return u

def worker_auth(req:Request):
    if len(WORKER_TOKEN)<32 or not hmac.compare_digest(req.headers.get('authorization',''), 'Bearer '+WORKER_TOKEN): raise HTTPException(401,'Worker authentication failed')

# Additive column migrations for databases created by older versions.
COLUMNS={
    'sessions':{'created':'INTEGER DEFAULT 0 NOT NULL','agent':"VARCHAR(160) DEFAULT '' NOT NULL"},
    'orders':{'coupon':"VARCHAR(32) DEFAULT '' NOT NULL"},
    'users':{'ref_code':"VARCHAR(12) DEFAULT '' NOT NULL",'referred_by':"VARCHAR(32) DEFAULT '' NOT NULL",'prefs':"TEXT DEFAULT '{}' NOT NULL",'max_tabs':'INTEGER DEFAULT 20 NOT NULL','last_login':'INTEGER DEFAULT 0 NOT NULL','note':"VARCHAR(300) DEFAULT '' NOT NULL"},
    'tabs':{'group':"VARCHAR(40) DEFAULT '' NOT NULL",'boot':'INTEGER DEFAULT 0 NOT NULL','restart_at':"VARCHAR(5) DEFAULT '' NOT NULL",
            'last_restart':'INTEGER DEFAULT 0 NOT NULL','notified_expiry':'INTEGER DEFAULT 0 NOT NULL','custom_jar_id':'VARCHAR(32)','auto_renew':'INTEGER DEFAULT 0 NOT NULL','screen':"VARCHAR(12) DEFAULT '240x320' NOT NULL"},
    'custom_jars':{'sha256':"VARCHAR(64) DEFAULT '' NOT NULL",'status':"VARCHAR(12) DEFAULT 'pending' NOT NULL",'kind':"VARCHAR(8) DEFAULT 'jar' NOT NULL",'screen':"VARCHAR(12) DEFAULT '240x320' NOT NULL",'midlet':"VARCHAR(160) DEFAULT '' NOT NULL"},
    'commands':{'text':"VARCHAR(64) DEFAULT '' NOT NULL"},
}
def migrate():
    existing={t:{c['name'] for c in inspect(engine).get_columns(t)} for t in COLUMNS}
    with engine.begin() as conn:
        for table,cols in COLUMNS.items():
            for name,ddl in cols.items():
                if name not in existing[table]: conn.exec_driver_sql(f'ALTER TABLE {table} ADD COLUMN "{name}" {ddl}')

@asynccontextmanager
async def lifespan(app):
    Base.metadata.create_all(engine)
    migrate()
    import threading
    stop=threading.Event()
    if SEPAY_API_TOKEN and live_payment(): threading.Thread(target=sepay_loop,args=(stop,),daemon=True).start()
    with tx() as s:
        if not s.get(Worker,'local-1'): s.add(Worker(id='local-1',capacity=int(os.getenv('WORKER_CAPACITY','4'))))
    yield
    stop.set()

app=FastAPI(title='ThuêTab API',version=VERSION,lifespan=lifespan,docs_url=None,redoc_url=None,openapi_url=None)
@app.middleware('http')
async def security(req, call_next):
    length=req.headers.get('content-length','0')
    cap=31_457_280 if req.url.path=='/api/jars/upload' else 2_000_000
    if not length.isdigit() or int(length)>cap: return Response('Payload too large',413)
    if req.method not in ('GET','HEAD','OPTIONS') and req.cookies.get('tt_session'):
        if req.headers.get('origin') not in (*ORIGINS, *DEV_ORIGINS):
            return Response('Invalid origin',403)
    res=await call_next(req)
    res.headers['X-Content-Type-Options']='nosniff'
    res.headers['Referrer-Policy']='same-origin'
    res.headers['X-Frame-Options']='DENY'
    res.headers['Permissions-Policy']='camera=(), microphone=(), geolocation=()'
    if SECURE: res.headers['Strict-Transport-Security']='max-age=31536000'
    res.headers['Content-Security-Policy']="default-src 'self'; img-src 'self' blob: data: https://qr.sepay.vn; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    if req.url.path.startswith('/api'): res.headers['Cache-Control']='no-store'
    # Vite puts a content hash in every /assets file name, so browsers can keep them forever.
    elif req.url.path.startswith('/assets/'): res.headers['Cache-Control']='public, max-age=31536000, immutable'
    elif req.url.path.startswith(('/icons/','/art/','/favicon','/logo')): res.headers['Cache-Control']='public, max-age=86400'
    return res

from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(CORSMiddleware, allow_origins=[*ORIGINS, *DEV_ORIGINS], allow_credentials=True,
                   allow_methods=['GET','POST','PUT','PATCH','DELETE'], allow_headers=['content-type','authorization','x-filename'],
                   max_age=600)

class Credentials(BaseModel):
    email: str = Field(min_length=5,max_length=254)
    password: str = Field(min_length=10,max_length=128)
    name: str = Field(default='Game thủ',min_length=1,max_length=60)
    ref: str = Field(default='',max_length=12)

@app.get('/api/health')
def health():
    with Session() as s: s.execute(text('SELECT 1'))
    return {'ok':True}
@app.get('/api/config')
def config():
    return {
        # Public web address (Cloudflare Pages): share and referral links for the native app point here, never at the API.
        'web_url': ORIGINS[0],
        'plans': plans(),
        'games': [{'id':g['id'],'name':g['name'],'kind':g['kind'],'description':g['description'],'enabled':True,'icon':g.get('icon','custom')} for g in CATALOG if g['enabled']],
        'payment_ready': live_payment(),
        'is_live_payment': live_payment(),
        'trial_minutes': TRIAL_MINUTES,
        'max_tabs': 20,
        'jar_max_mb': 30,
        'jar_auto_approve': JAR_AUTO_APPROVE,
        'topup_presets': setting('topup_presets',[20000,50000,100000,200000,500000]),
        'screens': SCREENS,
        'auto_topup': live_payment(),
        'support': {**SUPPORT,**setting('support',{})},
        'site': {**SITE_DEFAULTS,**setting('site',{})},
        'downloads': downloads(),
        'referral': {k:features.referral()[k] for k in ('enabled','percent','max_bonus')},
        'maintenance': features.maintenance(),
    }
@app.get('/api/downloads/{name}')
def download_app(name:str):
    folder=(DATA_DIR/DOWNLOAD_DIR_NAME).resolve()
    f=(folder/name).resolve()
    if not f.is_relative_to(folder) or not f.is_file(): raise HTTPException(404,'Không tìm thấy bản tải.')
    return FileResponse(f,filename=f.name,media_type='application/octet-stream')
@app.get('/api/status')
def status():
    # Availability only: server counts, capacity and hostnames stay private (admin overview has them).
    with Session() as s:
        online=s.scalars(select(Worker).where(Worker.last_seen>now()-20,Worker.draining==0)).all()
        used=s.scalar(select(func.count()).select_from(Slot).where(Slot.expires>now(),Slot.worker_id.in_([w.id for w in online]))) if online else 0
        return {'online':bool(online),'accepting':sum(w.capacity for w in online)>used,'time':now()}
@app.post('/api/auth/register',status_code=201)
def register(b:Credentials, req:Request):
    limit('register:'+client_ip(req),5,3600)
    email=b.email.strip().lower()
    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',email): raise HTTPException(422,'Email không hợp lệ.')
    hashed=ph.hash(b.password)
    try:
        with tx() as s:
            inviter=s.scalar(select(User).where(User.ref_code==b.ref.strip().upper())) if b.ref.strip() else None
            s.add(User(id=uid(),email=email,password=hashed,name=b.name.strip() or 'Game thủ',referred_by=inviter.id if inviter else ''))
    except IntegrityError: raise HTTPException(409,'Email đã được sử dụng.')
    return {'ok':True}
@app.post('/api/auth/login')
def login(b:Credentials,req:Request,res:Response):
    email=b.email.strip().lower()
    limit('login-ip:'+client_ip(req),30,600)
    limit('login-user:'+hashlib.sha256(email.encode()).hexdigest(),10,600)
    with tx() as s:
        u=s.scalar(select(User).where(User.email==email))
        valid=False
        if u:
            try: valid=ph.verify(u.password,b.password)
            except (VerifyMismatchError,InvalidHashError): pass
        if not valid or u.blocked: raise HTTPException(401,'Email hoặc mật khẩu không đúng.')
        token=secrets.token_urlsafe(32)
        u.last_login=now()
        s.add(AuthSession(hash=hashlib.sha256(token.encode()).hexdigest(), user_id=u.id,expires=now()+SESSION_SECONDS,created=now(),agent=req.headers.get('user-agent','')[:160]))
        res.set_cookie('tt_session',token,httponly=True,secure=SECURE,samesite='strict',max_age=SESSION_SECONDS)
        return {'user':public_user(u),'token':token}
@app.post('/api/auth/logout')
def logout(req:Request,res:Response,u=Depends(current)):
    token=req.headers.get('authorization','').removeprefix('Bearer ') or req.cookies.get('tt_session','')
    with tx() as s: s.execute(delete(AuthSession).where(AuthSession.hash==hashlib.sha256(token.encode()).hexdigest()))
    res.delete_cookie('tt_session')
    return {'ok':True}
@app.get('/api/me')
def me(u=Depends(current)): return public_user(u)
@app.patch('/api/me/prefs')
def edit_prefs(b:dict=Body(...),u=Depends(current)):
    clean={}
    for k,v in b.items():
        allowed=PREF_CHOICES.get(k,'missing')
        if allowed=='missing': raise HTTPException(422,f'Cài đặt không hợp lệ: {k}')
        ok=isinstance(v,bool) if allowed is bool else (v in SCREEN_IDS if k=='default_screen' else (not isinstance(v,bool) and v in allowed))
        if not ok: raise HTTPException(422,f'Giá trị không hợp lệ cho {k}.')
        clean[k]=v
    with tx() as s:
        x=lock(s,User,u.id)
        x.prefs=json.dumps({**json.loads(x.prefs or '{}'),**clean})
        return public_user(x)
class Profile(BaseModel): name:str=Field(min_length=1,max_length=60)
@app.patch('/api/me')
def edit_me(b:Profile,u=Depends(current)):
    with tx() as s:
        x=lock(s,User,u.id);x.name=b.name.strip() or x.name
        return public_user(x)
class Password(BaseModel):
    old: str = Field(min_length=1,max_length=128)
    new: str = Field(min_length=10,max_length=128)
@app.post('/api/me/password')
def change_password(b:Password,req:Request,u=Depends(current)):
    limit('password:'+u.id,5,600)
    try: ph.verify(u.password,b.old)
    except (VerifyMismatchError,InvalidHashError): raise HTTPException(403,'Mật khẩu hiện tại không đúng.')
    keep=hashlib.sha256(session_token(req).encode()).hexdigest()
    with tx() as s:
        lock(s,User,u.id).password=ph.hash(b.new)
        # Sign out every other device.
        s.execute(delete(AuthSession).where(AuthSession.user_id==u.id,AuthSession.hash!=keep))
        audit(s,u.id,'user.password',u.id)
    return {'ok':True}
@app.post('/api/auth/logout-all')
def logout_all(res:Response,u=Depends(current)):
    with tx() as s: s.execute(delete(AuthSession).where(AuthSession.user_id==u.id))
    res.delete_cookie('tt_session')
    return {'ok':True}
@app.get('/api/tabs')
def tabs(u=Depends(current)):
    with Session() as s: return [tab_dict(t) for t in s.scalars(select(Tab).where(Tab.user_id==u.id).order_by(Tab.created.desc()))]
@app.get('/api/jars')
def list_jars(u=Depends(current)):
    with Session() as s:
        jars = s.scalars(select(CustomJar).where(CustomJar.user_id==u.id).order_by(CustomJar.created.desc())).all()
        return [jar_dict(j) for j in jars]

MAX_JARS_PER_USER = 50
@app.post('/api/jars/upload')
async def upload_jar(req:Request,u=Depends(current)):
    limit('jar-upload:'+u.id, 10, 300)
    raw_name = req.headers.get('x-filename', '')
    from urllib.parse import unquote
    filename = unquote(raw_name).strip() if raw_name else 'custom.jar'
    if not filename.lower().endswith('.jar'):
        filename += '.jar'
    content = await req.body()
    if len(content) > 31_457_280:
        raise HTTPException(413, 'Dung lượng file vượt quá giới hạn 30MB.')
    if len(content) < 4 or not content.startswith(b'PK\x03\x04'):
        raise HTTPException(422, 'File không phải là file JAR (định dạng zip chuẩn).')
    kind, midlet, screen = inspect_jar(content)
    digest = hashlib.sha256(content).hexdigest()
    with Session() as s:
        # The same file again (double click, re-upload): hand back the copy already stored, no second file.
        same = s.scalar(select(CustomJar).where(CustomJar.user_id==u.id, CustomJar.sha256==digest, CustomJar.status!='rejected'))
        if same: return {'ok':True,'jar':jar_dict(same),'duplicate':True}
        if u.role!='admin' and s.scalar(select(func.count()).select_from(CustomJar).where(CustomJar.user_id==u.id))>=MAX_JARS_PER_USER:
            raise HTTPException(409, f'Bạn đã có {MAX_JARS_PER_USER} file JAR. Hãy xoá bớt file không dùng trước khi tải lên.')
    jar_id = uid()
    (JAR_DIR / f"{jar_id}.jar").write_bytes(content)
    with tx() as s:
        cjar = CustomJar(id=jar_id, user_id=u.id, filename=filename[:120], file_size=len(content), sha256=digest, kind=kind, midlet=midlet, screen=screen, status='approved' if JAR_AUTO_APPROVE or u.role=='admin' else 'pending')
        s.add(cjar); s.flush()
        audit(s,u.id,'jar.upload',jar_id)
        return {'ok':True,'jar':jar_dict(cjar)}

@app.delete('/api/jars/{id}')
def delete_jar(id:str,u=Depends(current)):
    with tx() as s:
        cjar = s.scalar(select(CustomJar).where(CustomJar.id==id, CustomJar.user_id==u.id))
        if not cjar: raise HTTPException(404, 'Không tìm thấy file JAR.')
        using = s.scalar(select(Tab).where(Tab.custom_jar_id==id, Tab.expires>now()))
        if using: raise HTTPException(409, f'File đang được dùng ở tab "{using.name}". Hãy đổi game của tab đó trước.')
        s.delete(cjar)
        f = JAR_DIR / f"{id}.jar"
        if f.exists(): f.unlink()
    return {'ok':True}

def resolve_game(s,u,game,jar_id):
    if not game: return None  # tab rented now, game chosen later
    if not any(g['id']==game and g['enabled'] for g in CATALOG): raise HTTPException(422,'Game này chưa mở.')
    if game!='custom-jar': return None
    if not jar_id: raise HTTPException(422,'Vui lòng chọn file JAR.')
    cjar=s.get(CustomJar,jar_id)
    if not cjar or cjar.user_id!=u.id: raise HTTPException(404,'File JAR không tồn tại hoặc không thuộc tài khoản của bạn.')
    if cjar.status!='approved': raise HTTPException(409,'File JAR chưa được phép chạy.')
    return jar_id
def pick_screen(s,screen,jar_id):
    if screen:
        if screen not in SCREEN_IDS: raise HTTPException(422,'Kích thước màn hình không hợp lệ.')
        return screen
    j=s.get(CustomJar,jar_id) if jar_id else None
    return j.screen if j and j.screen in SCREEN_IDS else '240x320'
class Rent(BaseModel):
    name: str = Field(min_length=1,max_length=60)
    game: str | None = None
    plan: str = 'month'
    trial: bool = False
    slot_id: str | None = None
    custom_jar_id: str | None = None
    screen: str | None = None
    coupon: str = Field(default='',max_length=32)
@app.post('/api/tabs',status_code=201)
def rent(b:Rent,u=Depends(current)):
    limit('rent:'+u.id,10,60)
    features.ensure_open(u)
    p=next((p for p in plans() if p['id']==b.plan),None)
    if not p: raise HTTPException(422,'Gói thuê không hợp lệ.')
    with tx() as s:
        owner=lock(s,User,u.id)
        if b.trial and (not owner.trial_approved or owner.trial_used): raise HTTPException(403,'Dùng thử cần được admin duyệt và chỉ nhận một lần.')
        # Double click / resent request: the same rental a few seconds ago is not charged a second time.
        if s.scalar(select(Tab.id).where(Tab.user_id==u.id,Tab.name==b.name.strip(),Tab.game==b.game,Tab.created>now()-5)):
            raise HTTPException(409,'Tab này vừa được tạo. Kiểm tra danh sách tab trước khi thuê thêm.')
        jar_id=resolve_game(s,u,b.game,b.custom_jar_id)
        existing_slot=lock(s,Slot,b.slot_id) if b.slot_id else None
        if b.slot_id:
            if b.trial or not existing_slot or existing_slot.user_id!=u.id or existing_slot.expires<=now(): raise HTTPException(409,'Slot không khả dụng.')
            if s.scalar(select(Tab).where(Tab.slot_id==b.slot_id)): raise HTTPException(409,'Slot đang được sử dụng.')
        price=0 if b.trial or existing_slot else p['price']
        price,code=features.discounted(s,b.coupon,owner,price) if price else (0,'')
        if owner.balance<price: raise HTTPException(409,'Số dư chưa đủ. Hãy nạp thêm vào ví.')
        active=s.scalar(select(func.count()).select_from(Tab).where(Tab.user_id==u.id,Tab.expires>now()))
        if active>=owner.max_tabs: raise HTTPException(409,f'Giới hạn {owner.max_tabs} tab/tài khoản. Liên hệ hỗ trợ để nâng hạn mức.')
        workers=s.scalars(select(Worker).where(Worker.last_seen>now()-20,Worker.draining==0).order_by(Worker.id).with_for_update()).all()
        chosen=None
        for w in workers:
            if existing_slot:
                if w.id==existing_slot.worker_id: chosen=w; break
            else:
                occupied=s.scalar(select(func.count()).select_from(Slot).where(Slot.worker_id==w.id,Slot.expires>now()))
                if occupied<w.capacity: chosen=w; break
        if not chosen: raise HTTPException(409,'Hệ thống tạm hết chỗ, vui lòng thử lại sau. Chưa trừ tiền.')
        slot=existing_slot or Slot(id=uid(),user_id=u.id,worker_id=chosen.id,plan='trial' if b.trial else p['id'],expires=now()+(TRIAL_MINUTES*60 if b.trial else p['days']*86400))
        if not existing_slot: s.add(slot)
        t=Tab(slot_id=slot.id,id=uid(),user_id=u.id,worker_id=chosen.id,custom_jar_id=jar_id,screen=pick_screen(s,b.screen,jar_id),name=b.name.strip() or 'Tab mới',game=b.game or '',plan=slot.plan,expires=slot.expires)
        if not t.game: t.status='idle'
        owner.balance-=price
        if b.trial: owner.trial_used=1
        s.add(t);s.add(Ledger(id=uid(),user_id=u.id,amount=-price,description=('Thuê tab '+t.name+(f' (mã {code})' if code else ''))[:160]))
        audit(s,u.id,'tab.rent',t.id);s.flush()
        return tab_dict(t)
def restart(t):
    if t.desired=='running': t.status='queued'
    (FRAME_DIR/(t.id+'.png')).unlink(missing_ok=True)
def owned(s,id,u):
    t=lock(s,Tab,id)
    if not t or (t.user_id!=u.id and u.role!='admin'): raise HTTPException(404,'Không tìm thấy tab.')
    return t
class EditTab(BaseModel):
    name: str | None = Field(default=None,min_length=1,max_length=60)
    desired: str | None = None
    auto_renew: bool | None = None
    game: str | None = None
    custom_jar_id: str | None = None
    screen: str | None = None
@app.patch('/api/tabs/{id}')
def edit_tab(id:str,b:EditTab,u=Depends(current)):
    with tx() as s:
        t=owned(s,id,u)
        if b.name is not None: t.name=b.name.strip() or 'Tab mới'
        if b.desired is not None:
            if b.desired not in ('running','stopped'): raise HTTPException(422,'Lệnh không hợp lệ.')
            if t.expires<=now(): raise HTTPException(409,'Tab đã hết hạn.')
            t.desired=b.desired
        if b.game is not None:
            # A tab is a rented sandbox, not a game: switching restarts it with the new game/JAR.
            jar_id=resolve_game(s,u if t.user_id==u.id else s.get(User,t.user_id),b.game,b.custom_jar_id)
            if (b.game,jar_id)!=(t.game,t.custom_jar_id):
                t.game=b.game;t.custom_jar_id=jar_id;t.error=''
                if b.screen is None: t.screen=pick_screen(s,None,jar_id)
                restart(t)
        if b.screen is not None and b.screen!=t.screen:
            # Rotating means relaunching the emulator at the new size.
            t.screen=pick_screen(s,b.screen,None);restart(t)
        if b.auto_renew is not None:
            if b.auto_renew and t.plan=='trial': raise HTTPException(409,'Tab dùng thử không gia hạn tự động được.')
            t.auto_renew=int(b.auto_renew)
        audit(s,u.id,'tab.update',id)
        return tab_dict(t)
class Renew(BaseModel):
    plan: str
    coupon: str = Field(default='',max_length=32)
@app.post('/api/tabs/{id}/renew')
def renew(id:str,b:Renew,u=Depends(current)):
    limit('renew:'+id,1,5)  # a double click must not charge two renewals
    p=next((p for p in plans() if p['id']==b.plan),None)
    if not p: raise HTTPException(422,'Gói không hợp lệ.')
    with tx() as s:
        owner=lock(s,User,u.id)
        t=owned(s,id,u)
        if t.user_id!=u.id: raise HTTPException(403,'Chỉ chủ tab được gia hạn bằng ví của mình.')
        w=lock(s,Worker,t.worker_id)
        if not w or w.last_seen<now()-20 or w.draining: raise HTTPException(409,'Hệ thống đang bảo trì, vui lòng thử lại sau.')
        if t.expires<=now():
            count=s.scalar(select(func.count()).select_from(Slot).where(Slot.worker_id==w.id,Slot.expires>now()))
            if count>=w.capacity: raise HTTPException(409,'Hệ thống tạm hết chỗ, vui lòng thử lại sau.')
        price,code=features.discounted(s,b.coupon,owner,p['price'])
        if owner.balance<price: raise HTTPException(409,'Số dư không đủ.')
        owner.balance-=price;t.expires=max(now(),t.expires)+p['days']*86400;t.plan=p['id'];t.desired='running';t.notified_expiry=0
        slot=lock(s,Slot,t.slot_id)
        if slot: slot.expires=t.expires;slot.plan=t.plan
        s.add(Ledger(id=uid(),user_id=u.id,amount=-price,description=('Gia hạn '+t.name+(f' (mã {code})' if code else ''))[:160]));audit(s,u.id,'tab.renew',id)
        return tab_dict(t)

def slot_dict(s, slot):
    tab=s.scalar(select(Tab).where(Tab.slot_id==slot.id))
    return {'id':slot.id,'plan':slot.plan,'expires':slot.expires,'created':slot.created,'tab_id':tab.id if tab else None,'tab_name':tab.name if tab else None}
@app.get('/api/slots')
def get_slots(u=Depends(current)):
    with Session() as s: return [slot_dict(s,x) for x in s.scalars(select(Slot).where(Slot.user_id==u.id).order_by(Slot.created.desc()))]
class BuySlots(BaseModel):
    quantity: int = Field(ge=1,le=20,strict=True)
    plan: str = 'month'
    coupon: str = Field(default='',max_length=32)
@app.post('/api/slots',status_code=201)
def buy_slots(b:BuySlots,u=Depends(current)):
    limit('slots:'+u.id,10,60)
    p=next((p for p in plans() if p['id']==b.plan),None)
    if not p: raise HTTPException(422,'Gói không hợp lệ.')
    with tx() as s:
        owner=lock(s,User,u.id)
        active=s.scalar(select(func.count()).select_from(Slot).where(Slot.user_id==u.id,Slot.expires>now()))
        if active+b.quantity>owner.max_tabs: raise HTTPException(409,f'Tối đa {owner.max_tabs} slot còn hạn/tài khoản.')
        features.ensure_open(u)
        total,code=features.discounted(s,b.coupon,owner,p['price']*b.quantity)
        if owner.balance<total: raise HTTPException(409,'Số dư không đủ.')
        workers=s.scalars(select(Worker).where(Worker.last_seen>now()-20,Worker.draining==0).order_by(Worker.id).with_for_update()).all()
        free=[]
        for w in workers:
            used=s.scalar(select(func.count()).select_from(Slot).where(Slot.worker_id==w.id,Slot.expires>now()))
            free += [w.id]*max(0,w.capacity-used)
        if len(free)<b.quantity: raise HTTPException(409,'Hệ thống tạm hết chỗ. Chưa trừ tiền.')
        result=[]
        for worker in free[:b.quantity]:
            slot=Slot(id=uid(),user_id=u.id,worker_id=worker,plan=p['id'],expires=now()+p['days']*86400)
            s.add(slot);s.flush();result.append(slot_dict(s,slot))
        owner.balance-=total
        s.add(Ledger(id=uid(),user_id=u.id,amount=-total,description=f"Mua {b.quantity} slot / {p['days']} ngày"))
        audit(s,u.id,'slots.buy',str(b.quantity))
        return result
@app.post('/api/slots/{id}/renew')
def renew_slot(id:str,b:Renew,u=Depends(current)):
    limit('renew-slot:'+id,1,5)
    p=next((p for p in plans() if p['id']==b.plan),None)
    if not p: raise HTTPException(422,'Gói không hợp lệ.')
    with tx() as s:
        owner=lock(s,User,u.id)
        slot=lock(s,Slot,id)
        if not slot or slot.user_id!=u.id: raise HTTPException(404,'Không tìm thấy slot.')
        w=lock(s,Worker,slot.worker_id)
        if not w or w.last_seen<now()-20 or w.draining: raise HTTPException(409,'Hệ thống đang bảo trì, vui lòng thử lại sau.')
        if slot.expires<=now():
            count=s.scalar(select(func.count()).select_from(Slot).where(Slot.worker_id==w.id,Slot.expires>now()))
            if count>=w.capacity: raise HTTPException(409,'Hệ thống tạm hết chỗ, vui lòng thử lại sau.')
        if owner.balance<p['price']: raise HTTPException(409,'Số dư không đủ.')
        owner.balance-=p['price'];slot.expires=max(now(),slot.expires)+p['days']*86400;slot.plan=p['id']
        t=s.scalar(select(Tab).where(Tab.slot_id==id).with_for_update())
        if t: t.expires=slot.expires;t.plan=slot.plan
        s.add(Ledger(id=uid(),user_id=u.id,amount=-p['price'],description='Gia hạn slot '+id[:8]))
        audit(s,u.id,'slot.renew',id)
        return slot_dict(s,slot)
@app.delete('/api/tabs/{id}')
def release_tab(id:str,u=Depends(current)):
    with tx() as s:
        t=owned(s,id,u)
        if t.desired!='stopped' or t.status not in ('stopped','expired','error'): raise HTTPException(409,'Hãy dừng tab và đợi worker xác nhận trước khi giải phóng.')
        s.delete(t);audit(s,u.id,'tab.release',id)
    (FRAME_DIR/(id+'.png')).unlink(missing_ok=True);(LOG_DIR/(id+'.txt')).unlink(missing_ok=True)
    return {'ok':True}

@app.get('/api/tabs/{id}/frame')
def frame(id:str,u=Depends(current)):
    with Session() as s:
        t=owned(s,id,u)
        if t.expires<=now(): raise HTTPException(409,'Tab đã hết hạn.')
    hub.thumb_seen[id]=time.monotonic()
    live=hub.recent(id,max_age=20)
    if live: return Response(live,media_type='image/jpeg',headers={'Cache-Control':'no-store'})
    path=FRAME_DIR/(id+'.png')
    if not path.exists() or time.time()-path.stat().st_mtime>20: raise HTTPException(404,'Chưa có hình ảnh mới.')
    return FileResponse(path,media_type='image/png',headers={'Cache-Control':'no-store'})

def stream_check(token,id):
    # Returns (tab kind, error code) for a viewer connection.
    u=user_for(token)
    if not u: return None,4401
    with Session() as s:
        t=s.get(Tab,id)
        if not t or (t.user_id!=u.id and u.role!='admin'): return None,4404
        if t.expires<=now() or t.desired!='running': return None,4409
        j=s.get(CustomJar,t.custom_jar_id) if t.custom_jar_id else None
        kind=j.kind if j else next((g.get('runtime','jar') for g in CATALOG if g['id']==t.game),'jar')
        return (kind,t.screen if kind=='midp' else '640x480'),0

def viewer_input(m):
    """Validate one input message from a viewer; returns the worker command or None."""
    kind=m.get('type')
    if kind=='key' and m.get('key') in KEYS: return {'key':m['key']}
    if kind=='text' and isinstance(m.get('text'),str) and 1<=len(m['text'])<=64 and re.fullmatch(r'[\x20-\x7e]+',m['text']): return {'text':m['text']}
    if kind=='tap':
        try: b=Tap(**{k:m.get(k) for k in ('x','y','x2','y2')})
        except Exception: return None
        if b.x2 is not None and b.y2 is not None: return {'key':'@swipe','text':f'{b.x},{b.y},{b.x2},{b.y2}'}
        return {'key':'@tap','text':f'{b.x},{b.y}'}
    return None

def share_check(token,id):
    with Session() as s:
        x,t=features.share_lookup(s,token)
        if not x or t.id!=id: return None,4404
        if t.desired!='running': return None,4409
        j=s.get(CustomJar,t.custom_jar_id) if t.custom_jar_id else None
        kind=j.kind if j else next((g.get('runtime','jar') for g in CATALOG if g['id']==t.game),'jar')
        return (kind,t.screen if kind=='midp' else '640x480',bool(x.can_control)),0

@app.websocket('/api/tabs/{id}/stream')
async def stream_view(ws:WebSocket,id:str):
    share=ws.query_params.get('share','')
    # Browsers can't set headers on a WebSocket, so a front-end on another site (Cloudflare Pages) sends its
    # bearer token as a subprotocol: new WebSocket(url, ['bearer', token]). The server echoes 'bearer'.
    protos=[x.strip() for x in ws.headers.get('sec-websocket-protocol','').split(',') if x.strip()]
    proto_token=protos[1] if len(protos)>=2 and protos[0]=='bearer' else ''
    token=ws.headers.get('authorization','').removeprefix('Bearer ') or proto_token or ws.cookies.get('tt_session','')
    origin=ws.headers.get('origin')
    # Cookie auth from browsers must come from an allowed origin (blocks cross-site WebSocket hijacking).
    # Bearer tokens and share tokens are never sent automatically, so they don't need that check.
    if not share and not ws.headers.get('authorization') and not proto_token and origin not in (*ORIGINS, *DEV_ORIGINS):
        await ws.close(code=4403); return
    check=(lambda: share_check(share,id)) if share else (lambda: stream_check(token,id))
    info,err=await run_in_threadpool(check)
    can_control=info[2] if share and info else True
    await ws.accept(subprotocol='bearer' if proto_token else None)
    if err: await ws.close(code=err); return
    try: fps=int(ws.query_params.get('fps','30'))
    except ValueError: fps=30
    viewer=Viewer(ws,fps if fps in FPS_CHOICES else 30,'h264' if ws.query_params.get('codec')=='h264' else 'mjpeg',ws.query_params.get('ack')=='1')
    if not hub.add_viewer(id,viewer): await ws.close(code=4429); return
    kind,screen=info[0],info[1]
    w,h=map(int,screen.split('x'))
    await ws.send_text(json.dumps({'type':'hello','kind':kind,'width':w,'height':h,'fps':viewer.fps}))
    pump=asyncio.create_task(viewer.pump())
    bucket,refill,checked=40.0,time.monotonic(),time.monotonic()
    try:
        while True:
            try: raw=await asyncio.wait_for(ws.receive_text(),timeout=10)
            except asyncio.TimeoutError: raw=None
            t=time.monotonic()
            if t-checked>10:
                checked=t
                if (await run_in_threadpool(check))[1]: await ws.close(code=4409); break
            if raw is None: continue
            # Frame acknowledgements arrive once per frame (up to 60/s): handled before the input rate limit.
            if raw=='{"type":"ack"}': viewer.acked();continue
            bucket=min(40.0,bucket+(t-refill)*30);refill=t
            if bucket<1: continue
            bucket-=1
            try: m=json.loads(raw)
            except ValueError: continue
            if not isinstance(m,dict): continue
            if m.get('type')=='fps' and m.get('fps') in FPS_CHOICES: viewer.fps=m['fps'];hub.retune(id);continue
            # Latency probe: echo the client's timestamp straight back.
            if m.get('type')=='ping': await ws.send_text(json.dumps({'type':'pong','t':m.get('t')}));continue
            cmd=viewer_input(m)
            if cmd and not can_control: await ws.send_text(json.dumps({'type':'error','detail':'Liên kết này chỉ cho phép xem.'}));continue
            if not cmd: await ws.send_text(json.dumps({'type':'error','detail':'Thao tác không hợp lệ.'}));continue
            if not await hub.forward(id,cmd):
                # Stream not up yet: fall back to the heartbeat queue.
                def queue():
                    with tx() as s:
                        t=s.get(Tab,id)
                        if t: queue_input(s,t,key=cmd.get('key',''),text=cmd.get('text',''))
                await run_in_threadpool(queue)
    except (WebSocketDisconnect,RuntimeError): pass
    finally:
        pump.cancel();hub.remove_viewer(id,viewer)

@app.websocket('/api/internal/stream/{id}')
async def stream_worker(ws:WebSocket,id:str):
    if len(WORKER_TOKEN)<32 or not hmac.compare_digest(ws.headers.get('authorization',''),'Bearer '+WORKER_TOKEN) or not re.fullmatch('[a-f0-9]{24}',id):
        await ws.close(code=4401); return
    await ws.accept()
    old=hub.workers.get(id)
    hub.workers[id]=ws
    if old:
        try: await old.close()
        except Exception: pass
    try:
        while True:
            frame=await ws.receive_bytes()
            # One publisher per tab: a replaced connection may still deliver a few queued frames before it closes,
            # and mixing two encoders' frames corrupts the video.
            if hub.workers.get(id) is not ws: break
            # JPEG frames, or H.264 access units (Annex B, start code first).
            if len(frame)<=400000 and frame[:3] in (b'\xff\xd8\xff',b'\x00\x00\x00',b'\x00\x00\x01'): hub.publish(id,frame)
    except (WebSocketDisconnect,RuntimeError,KeyError): pass
    finally:
        if hub.workers.get(id) is ws: hub.workers.pop(id,None)
class Key(BaseModel): key:str
# F1/F2 are the left/right soft keys in MicroEmulator.
KEYS={'Up','Down','Left','Right','Return','Escape','space','BackSpace','F1','F2','asterisk','numbersign','0','1','2','3','4','5','6','7','8','9'}
def queue_input(s,t,key='',text=''):
    if t.expires<=now() or t.desired!='running': raise HTTPException(409,'Tab không hoạt động.')
    s.add(Command(id=uid(),tab_id=t.id,key=key,text=text))
@app.post('/api/tabs/{id}/input')
def game_input(id:str,b:Key,u=Depends(current)):
    limit('input:'+u.id,240,60)
    if b.key not in KEYS: raise HTTPException(422,'Phím không hỗ trợ.')
    with tx() as s: queue_input(s,owned(s,id,u),key=b.key)
    return {'ok':True}
class Text(BaseModel): text:str=Field(min_length=1,max_length=64)
@app.post('/api/tabs/{id}/text')
def game_text(id:str,b:Text,u=Depends(current)):
    limit('input:'+u.id,240,60)
    if not re.fullmatch(r'[\x20-\x7e]+',b.text): raise HTTPException(422,'Chỉ hỗ trợ chữ không dấu, số và ký hiệu cơ bản.')
    with tx() as s: queue_input(s,owned(s,id,u),text=b.text)
    return {'ok':True}
class Tap(BaseModel):
    # Coordinates in frame pixels (J2ME 240x320, Java PC 640x480); x2/y2 turn the tap into a swipe.
    x: int = Field(ge=0,le=639)
    y: int = Field(ge=0,le=639)
    x2: int | None = Field(default=None,ge=0,le=639)
    y2: int | None = Field(default=None,ge=0,le=639)
@app.post('/api/tabs/{id}/tap')
def game_tap(id:str,b:Tap,u=Depends(current)):
    limit('input:'+u.id,240,60)
    swipe=b.x2 is not None and b.y2 is not None
    with tx() as s: queue_input(s,owned(s,id,u),key='@swipe' if swipe else '@tap',text=f'{b.x},{b.y},{b.x2},{b.y2}' if swipe else f'{b.x},{b.y}')
    return {'ok':True}
class SyncKey(BaseModel):
    tab_ids: list[str] = Field(min_length=1,max_length=20)
    key: str
@app.post('/api/tabs/input')
def sync_input(b:SyncKey,u=Depends(current)):
    # Same key to several of the user's running tabs (multi-instance sync control).
    limit('input:'+u.id,240,60)
    if b.key not in KEYS: raise HTTPException(422,'Phím không hỗ trợ.')
    sent=0
    with tx() as s:
        for id in dict.fromkeys(b.tab_ids):
            t=s.get(Tab,id)
            if t and t.user_id==u.id and t.expires>now() and t.desired=='running': queue_input(s,t,key=b.key);sent+=1
    return {'ok':True,'sent':sent}
@app.get('/api/wallet')
def wallet(u=Depends(current)):
    with Session() as s:
        ledger=s.scalars(select(Ledger).where(Ledger.user_id==u.id).order_by(Ledger.created.desc()).limit(100))
        orders=s.scalars(select(Order).where(Order.user_id==u.id).order_by(Order.created.desc()).limit(100))
        return {'balance':u.balance,'ledger':[{'id':x.id,'amount':x.amount,'description':x.description,'created':x.created} for x in ledger], 'orders':[order_info(x) for x in orders]}
def order_info(o):
    account=os.getenv('BANK_ACCOUNT','')
    bank=os.getenv('BANK_CODE','')
    is_live=live_payment()
    qr_url='https://qr.sepay.vn/img?'+urlencode({'acc':account,'bank':bank,'amount':o.amount,'des':o.code}) if is_live else ''
    return {'id':o.id,'code':o.code,'amount':o.amount,'status':o.status,'created':o.created,'coupon':o.coupon,'bank':bank,'account':account,'account_name':os.getenv('BANK_ACCOUNT_NAME',''),'qr_url':qr_url,'is_live':is_live}

class Topup(BaseModel):
    amount:int=Field(ge=10000,le=5000000,strict=True)
    coupon:str=Field(default='',max_length=32)

MAX_PENDING_ORDERS=3
@app.post('/api/wallet/orders',status_code=201)
def create_order(b:Topup,u=Depends(current)):
    limit('order:'+u.id,20,3600)
    if not live_payment(): raise HTTPException(503,'Nạp tiền đang tạm ngưng, vui lòng thử lại sau.')
    with tx() as s:
        lock(s,User,u.id)  # one order creation at a time per user (repeated taps)
        code=features.coupon_quote(s,b.coupon,u.id,'topup',b.amount)[0].code if b.coupon else ''
        # Repeated taps / the same amount again: hand back the order that is still waiting instead of a new one.
        same=s.scalar(select(Order).where(Order.user_id==u.id,Order.status=='pending',Order.amount==b.amount,
                                          Order.coupon==code,Order.created>now()-86400).order_by(Order.created.desc()))
        if same: return order_info(same)
        if s.scalar(select(func.count()).select_from(Order).where(Order.user_id==u.id,Order.status=='pending',Order.created>now()-86400))>=MAX_PENDING_ORDERS:
            raise HTTPException(409,f'Bạn đang có {MAX_PENDING_ORDERS} đơn nạp chờ thanh toán. Hãy thanh toán hoặc hủy bớt trước khi tạo đơn mới.')
        # TT + 10 digits fits SePay's default payment-code template (prefix TT, 3–10 digits).
        while True:
            pay_code='TT'+str(10**9+secrets.randbelow(9*10**9))
            if not s.scalar(select(Order.id).where(Order.code==pay_code)): break
        o=Order(id=uid(),user_id=u.id,code=pay_code,amount=b.amount,coupon=code)
        s.add(o);s.flush();return order_info(o)

@app.delete('/api/wallet/orders/{id}')
def cancel_order(id:str,u=Depends(current)):
    with tx() as s:
        o=s.scalar(select(Order).where(Order.id==id,Order.user_id==u.id).with_for_update())
        if not o or o.status!='pending': raise HTTPException(404,'Đơn nạp không tồn tại hoặc đã xử lý.')
        o.status='cancelled'
        return order_info(o)
@app.get('/api/tabs/{id}/logs')
def get_tab_logs(id:str,u=Depends(current)):
    with Session() as s:
        t=owned(s,id,u)
    hub.log_seen[id]=time.monotonic()
    path=LOG_DIR/(id+'.txt')
    text=path.read_text(errors='replace') if path.exists() else ''
    return {'id':id,'logs':text or 'Chưa có nhật ký từ game.','status':t.status,'updated':int(path.stat().st_mtime) if path.exists() else 0}
@app.post('/api/payments/sepay')
async def sepay(req:Request):
    secret=os.getenv('SEPAY_API_KEY','')
    if len(secret)<32 or not hmac.compare_digest(req.headers.get('authorization',''),'Apikey '+secret): raise HTTPException(401,'Invalid webhook credentials')
    try: b=await req.json()
    except Exception: raise HTTPException(400,'Invalid JSON')
    if not isinstance(b,dict): raise HTTPException(422,'Invalid payload')
    if b.get('transferType')!='in': return {'success':True,'ignored':True}
    # Anything we can't credit is acknowledged (2xx) so SePay doesn't retry it 7 times, and recorded in the audit
    # log for an admin to reconcile by hand (Quản trị → Đơn nạp → Xác nhận tay).
    def skip(reason):
        with tx() as s: audit(s,'sepay','payment.unmatched',f"{reason} id={b.get('id')} {b.get('transferAmount')}đ {str(b.get('content',''))[:40]}"[:80])
        return {'success':True,'matched':False,'reason':reason}
    if b.get('accountNumber')!=os.getenv('BANK_ACCOUNT') or b.get('gateway')!=os.getenv('BANK_NAME'):
        return skip(f"tk {b.get('gateway')}/{str(b.get('accountNumber'))[-4:]}")
    amount=b.get('transferAmount')
    if isinstance(amount,bool) or not isinstance(amount,(int,float)) or not float(amount).is_integer() or not 0<amount<=5000000: return skip('số tiền')
    transaction=str(b.get('id',''));reference=b.get('referenceCode')
    if not transaction.isdigit() or not isinstance(reference,str) or not 1<=len(reference)<=100: return skip('thiếu mã GD')
    result=credit(transaction,reference,int(amount),str(b.get('content','')),b.get('code'),'sepay')
    if result=='unmatched': return skip('không khớp đơn')
    if result=='conflict': raise HTTPException(409,'Payment conflict; manual reconciliation required')
    return {'success':True,'matched':True,'duplicate':result=='duplicate'}

def credit(transaction,reference,amount,content,code,source):
    """Credit one bank transfer to its order exactly once. Returns credited|duplicate|unmatched|conflict."""
    # Current codes: TT + 10 digits; older orders used TT + 12 hex characters.
    pattern=r'TT(?:\d{10}|[A-F0-9]{12})'
    codes=set(re.findall(r'(?<![A-Z0-9])'+pattern+r'(?![A-Z0-9])',content.upper()))
    if code and re.fullmatch(pattern,str(code).upper()): codes.add(str(code).upper())
    ref=os.getenv('BANK_NAME','')+':'+reference
    try:
        with tx() as s:
            if s.get(Payment,transaction) or s.scalar(select(Payment).where(Payment.reference==ref)): return 'duplicate'
            if len(codes)!=1: return 'unmatched'
            o=s.scalar(select(Order).where(Order.code==next(iter(codes))).with_for_update())
            # A transfer that arrives after the user cancelled still belongs to them.
            if not o or o.amount!=amount or o.status not in ('pending','cancelled'): return 'unmatched'
            owner=lock(s,User,o.user_id)
            s.add(Payment(id=transaction,reference=ref,order_id=o.id,amount=amount))
            owner.balance+=amount;o.status='paid'
            s.add(Ledger(id=uid(),user_id=owner.id,amount=amount,description='Nạp tiền tự động '+o.code))
            s.flush();features.on_payment(s,o,owner)
            audit(s,source,'payment.credit',o.id)
            return 'credited'
    except IntegrityError:
        with Session() as s:
            if s.get(Payment,transaction) or s.scalar(select(Payment).where(Payment.reference==ref)): return 'duplicate'
        return 'conflict'

SEPAY_API_TOKEN=os.getenv('SEPAY_API_TOKEN','')
def poll_sepay():
    # Backup for the webhook (e.g. server briefly offline): read recent incoming transfers from SePay.
    import httpx
    with Session() as s:
        if not s.scalar(select(Order.id).where(Order.status=='pending',Order.created>now()-86400).limit(1)): return 0
    r=httpx.get('https://my.sepay.vn/userapi/transactions/list',params={'account_number':os.getenv('BANK_ACCOUNT',''),'limit':50},
                headers={'Authorization':'Bearer '+SEPAY_API_TOKEN},timeout=10)
    r.raise_for_status()
    done=0
    for x in r.json().get('transactions') or []:
        try: amount=float(x.get('amount_in') or 0)
        except (TypeError,ValueError): continue
        tid=str(x.get('id',''))
        if not tid.isdigit() or not amount.is_integer() or not 0<amount<=5000000 or not x.get('reference_number'): continue
        done+=credit(tid,str(x['reference_number'])[:100],int(amount),str(x.get('transaction_content','')),x.get('code'),'sepay-poll')=='credited'
    return done
def sepay_loop(stop):
    while not stop.wait(30):
        try: poll_sepay()
        except Exception as e: print('SePay poll failed:',type(e).__name__,flush=True)
SYSTEM={}  # worker id -> latest system figures from its heartbeat (memory only: refreshed every few seconds)
_rate={'at':time.monotonic(),'out':0,'in':0,'out_bps':0,'in_bps':0}
@app.get('/api/admin/system')
def admin_system(u=Depends(admin)):
    """Live system view: each server's CPU/RAM/disk/network and tabs, viewers and stream bandwidth."""
    t=time.monotonic();dt=t-_rate['at']
    if dt>=1:
        _rate.update(out_bps=int((hub.bytes_out-_rate['out'])/dt),in_bps=int((hub.bytes_in-_rate['in'])/dt),out=hub.bytes_out,**{'in':hub.bytes_in},at=t)
    with Session() as s:
        names={x.id:x.name for x in s.scalars(select(Tab).where(Tab.status=='running'))}
        workers=[]
        for w in s.scalars(select(Worker)):
            sysd=SYSTEM.get(w.id,{})
            tabs=[{**x,'name':names.get(x.get('tab_id',''),'')} for x in sysd.get('tabs',[])]
            workers.append({'id':w.id,'online':w.last_seen>now()-20,'last_seen':w.last_seen,'capacity':w.capacity,
                            'running':s.scalar(select(func.count()).select_from(Tab).where(Tab.worker_id==w.id,Tab.status=='running')) or 0,
                            'system':{k:v for k,v in sysd.items() if k!='tabs'},'tabs':sorted(tabs,key=lambda x:-x.get('cpu',0))})
        return {'workers':workers,'live':{**hub.live(),'out_bps':_rate['out_bps'],'in_bps':_rate['in_bps']},
                'tabs':{'running':s.scalar(select(func.count()).select_from(Tab).where(Tab.status=='running')) or 0,
                        'total':s.scalar(select(func.count()).select_from(Tab)) or 0},
                'time':now()}

@app.get('/api/admin/overview')
def admin_overview(u=Depends(admin)):
    with Session() as s:
        rev = s.scalar(select(func.sum(Payment.amount))) or 0
        total_bal = s.scalar(select(func.sum(User.balance))) or 0
        return {
            'users':[admin_user(s,x) for x in s.scalars(select(User).order_by(User.created.desc()).limit(500))],
            'tabs':[internal_tab(x) for x in s.scalars(select(Tab).order_by(Tab.created.desc()).limit(200))],
            'orders':[{**order_info(x),'user_id':x.user_id} for x in s.scalars(select(Order).order_by(Order.created.desc()).limit(200))],
            'jars':[{**jar_dict(x),'user_id':x.user_id} for x in s.scalars(select(CustomJar).order_by(CustomJar.created.desc()).limit(200))],
            'workers':[{'id':x.id,'capacity':x.capacity,'last_seen':x.last_seen,'online':x.last_seen>now()-20,'draining':x.draining,'memory_mb':x.memory_mb,
                        'used':s.scalar(select(func.count()).select_from(Slot).where(Slot.worker_id==x.id,Slot.expires>now()))} for x in s.scalars(select(Worker))],
            'audit':[{'id':x.id,'action':x.action,'actor':x.actor,'target':x.target,'created':x.created} for x in s.scalars(select(Audit).order_by(Audit.created.desc()).limit(100))],
            'stats': {
                'total_revenue': rev,
                'total_users_balance': total_bal,
                'total_tabs': s.scalar(select(func.count()).select_from(Tab)) or 0,
                'active_tabs': s.scalar(select(func.count()).select_from(Tab).where(Tab.status=='running')) or 0,
                'pending_jars': s.scalar(select(func.count()).select_from(CustomJar).where(CustomJar.status=='pending')) or 0,
                'users': s.scalar(select(func.count()).select_from(User)) or 0,
                'open_tickets': s.scalar(select(func.count()).select_from(Ticket).where(Ticket.status=='open')) or 0
            }
        }
def admin_user(s,x):
    count=lambda m,*w: s.scalar(select(func.count()).select_from(m).where(m.user_id==x.id,*w)) or 0
    return {**public_user(x),'last_login':x.last_login,'note':x.note,
            'tabs':count(Tab),'running':count(Tab,Tab.status=='running',Tab.expires>now()),'jars':count(CustomJar),
            'paid':s.scalar(select(func.sum(Order.amount)).where(Order.user_id==x.id,Order.status=='paid')) or 0,
            'sessions':count(AuthSession,AuthSession.expires>now())}

def purge_user(s,user):
    """Delete a user and everything they own; returns files to remove after commit."""
    files=[]
    for t in s.scalars(select(Tab).where(Tab.user_id==user.id)): files+=[FRAME_DIR/(t.id+'.png'),LOG_DIR/(t.id+'.txt')]
    for j in s.scalars(select(CustomJar).where(CustomJar.user_id==user.id)): files.append(JAR_DIR/f'{j.id}.jar')
    for tk in s.scalars(select(Ticket.id).where(Ticket.user_id==user.id)): s.execute(delete(TicketMessage).where(TicketMessage.ticket_id==tk))
    for model in (Tab,Slot,CustomJar,Order,AuthSession,Ledger,Share,Ticket,Notification): s.execute(delete(model).where(model.user_id==user.id))
    s.delete(user)
    return files

def admins_left(s,excluding):
    return s.scalar(select(func.count()).select_from(User).where(User.role=='admin',User.blocked==0,User.id!=excluding)) or 0

@app.get('/api/admin/users/{id}')
def user_detail(id:str,u=Depends(admin)):
    with Session() as s:
        x=s.get(User,id)
        if not x: raise HTTPException(404,'Không tìm thấy người dùng.')
        return {'user':admin_user(s,x),
                'tabs':[internal_tab(t) for t in s.scalars(select(Tab).where(Tab.user_id==id).order_by(Tab.created.desc()))],
                'slots':[slot_dict(s,y) for y in s.scalars(select(Slot).where(Slot.user_id==id).order_by(Slot.created.desc()))],
                'jars':[jar_dict(j) for j in s.scalars(select(CustomJar).where(CustomJar.user_id==id).order_by(CustomJar.created.desc()))],
                'orders':[order_info(o) for o in s.scalars(select(Order).where(Order.user_id==id).order_by(Order.created.desc()).limit(100))],
                'ledger':[{'id':l.id,'amount':l.amount,'description':l.description,'created':l.created} for l in s.scalars(select(Ledger).where(Ledger.user_id==id).order_by(Ledger.created.desc()).limit(200))],
                'audit':[{'action':a.action,'actor':a.actor,'target':a.target,'created':a.created} for a in s.scalars(select(Audit).where((Audit.actor==id)|(Audit.target.like(id+'%'))).order_by(Audit.created.desc()).limit(100))]}

@app.delete('/api/admin/users/{id}')
def delete_user(id:str,u=Depends(admin)):
    if id==u.id: raise HTTPException(409,'Không thể tự xoá tài khoản của mình.')
    with tx() as s:
        x=lock(s,User,id)
        if not x: raise HTTPException(404,'Không tìm thấy người dùng.')
        if x.role=='admin' and not admins_left(s,id): raise HTTPException(409,'Phải còn ít nhất một quản trị viên.')
        files=purge_user(s,x);audit(s,u.id,'user.delete',x.email[:80])
    for f in files: f.unlink(missing_ok=True)
    return {'ok':True}

@app.post('/api/admin/users/{id}/password')
def reset_password(id:str,u=Depends(admin)):
    temp=secrets.token_urlsafe(9)
    with tx() as s:
        x=lock(s,User,id)
        if not x: raise HTTPException(404,'Không tìm thấy người dùng.')
        x.password=ph.hash(temp)
        s.execute(delete(AuthSession).where(AuthSession.user_id==id))
        audit(s,u.id,'user.password_reset',id)
    # Shown once to the admin; the user should change it after signing in.
    return {'password':temp}

@app.post('/api/admin/users/{id}/logout')
def force_logout(id:str,u=Depends(admin)):
    with tx() as s:
        n=s.execute(delete(AuthSession).where(AuthSession.user_id==id)).rowcount
        audit(s,u.id,'user.logout',id)
    return {'ok':True,'sessions':n}

class UserEdit(BaseModel):
    blocked: bool | None = None
    trial_approved: bool | None = None
    name: str | None = Field(default=None,min_length=1,max_length=60)
    email: str | None = Field(default=None,min_length=5,max_length=254)
    role: str | None = Field(default=None,pattern='^(user|admin)$')
    max_tabs: int | None = Field(default=None,ge=0,le=200)
    note: str | None = Field(default=None,max_length=300)
@app.patch('/api/admin/users/{id}')
def edit_user(id:str,b:UserEdit,u=Depends(admin)):
    with tx() as s:
        user=lock(s,User,id)
        if not user: raise HTTPException(404,'Không tìm thấy người dùng.')
        demoting=b.role=='user' and user.role=='admin'
        if (b.blocked or demoting) and (id==u.id or not admins_left(s,id)) and user.role=='admin':
            raise HTTPException(409,'Không thể khoá/hạ quyền chính mình hoặc quản trị viên cuối cùng.')
        if b.name is not None: user.name=b.name.strip() or user.name
        if b.email is not None:
            email=b.email.strip().lower()
            if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',email): raise HTTPException(422,'Email không hợp lệ.')
            if email!=user.email and s.scalar(select(User.id).where(User.email==email)): raise HTTPException(409,'Email đã được sử dụng.')
            user.email=email
        if b.role is not None: user.role=b.role
        if b.max_tabs is not None: user.max_tabs=b.max_tabs
        if b.note is not None: user.note=b.note.strip()
        if b.blocked is not None:
            user.blocked=int(b.blocked)
            if user.blocked:
                s.execute(delete(AuthSession).where(AuthSession.user_id==id))
                s.execute(update(Tab).where(Tab.user_id==id).values(desired='stopped'))
        if b.trial_approved is not None: user.trial_approved=int(b.trial_approved)
        audit(s,u.id,'user.update',id)
        return admin_user(s,user)

@app.delete('/api/admin/tabs/{id}')
def admin_delete_tab(id:str,release_slot:bool=False,u=Depends(admin)):
    # Force-remove a tab in any state; the worker drops its container on the next heartbeat.
    with tx() as s:
        t=lock(s,Tab,id)
        if not t: raise HTTPException(404,'Không tìm thấy tab.')
        if release_slot and t.slot_id: s.execute(delete(Slot).where(Slot.id==t.slot_id))
        s.delete(t);audit(s,u.id,'tab.admin_delete',id)
    (FRAME_DIR/(id+'.png')).unlink(missing_ok=True);(LOG_DIR/(id+'.txt')).unlink(missing_ok=True)
    return {'ok':True}

@app.delete('/api/admin/jars/{id}')
def admin_delete_jar(id:str,u=Depends(admin)):
    with tx() as s:
        j=lock(s,CustomJar,id)
        if not j: raise HTTPException(404,'Không tìm thấy file JAR.')
        # Tabs keep their rental and wait for the owner to pick another game.
        s.execute(update(Tab).where(Tab.custom_jar_id==id).values(game='',custom_jar_id=None,status='idle'))
        s.delete(j);audit(s,u.id,'jar.admin_delete',id)
    (JAR_DIR/f'{id}.jar').unlink(missing_ok=True)
    return {'ok':True}

@app.post('/api/admin/orders/{id}/cancel')
def admin_cancel_order(id:str,u=Depends(admin)):
    with tx() as s:
        o=s.scalar(select(Order).where(Order.id==id).with_for_update())
        if not o or o.status!='pending': raise HTTPException(404,'Đơn không tồn tại hoặc đã xử lý.')
        o.status='cancelled';audit(s,u.id,'order.cancel',id)
        return order_info(o)

class NewWorker(BaseModel):
    id: str = Field(pattern=r'^[a-z0-9-]{2,40}$')
    capacity: int = Field(ge=1,le=100)
@app.post('/api/admin/workers',status_code=201)
def add_worker(b:NewWorker,u=Depends(admin)):
    with tx() as s:
        if s.get(Worker,b.id): raise HTTPException(409,'Worker đã tồn tại.')
        s.add(Worker(id=b.id,capacity=b.capacity));audit(s,u.id,'worker.add',b.id)
    return {'ok':True}
@app.delete('/api/admin/workers/{id}')
def remove_worker(id:str,u=Depends(admin)):
    with tx() as s:
        w=lock(s,Worker,id)
        if not w: raise HTTPException(404,'Không tìm thấy worker.')
        if s.scalar(select(func.count()).select_from(Slot).where(Slot.worker_id==id,Slot.expires>now())): raise HTTPException(409,'Worker còn slot đang thuê. Bật "Ngừng nhận" và chờ hết hạn trước.')
        s.delete(w);audit(s,u.id,'worker.remove',id)
    return {'ok':True}

@app.get('/api/admin/stats')
def admin_stats(days:int=30,u=Depends(admin)):
    days=max(7,min(days,180));start=now()-days*86400
    import datetime
    day=lambda ts: datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d')
    keys=[day(start+86400*(i+1)) for i in range(days)]
    series={k:{'date':k,'topup':0,'spend':0,'signups':0,'rentals':0} for k in keys}
    with Session() as s:
        for o in s.scalars(select(Order).where(Order.status=='paid',Order.created>start)):
            if day(o.created) in series: series[day(o.created)]['topup']+=o.amount
        for l in s.scalars(select(Ledger).where(Ledger.amount<0,Ledger.created>start)):
            if day(l.created) in series: series[day(l.created)]['spend']-=l.amount
        for x in s.scalars(select(User.created).where(User.created>start)):
            if day(x) in series: series[day(x)]['signups']+=1
        for x in s.scalars(select(Tab.created).where(Tab.created>start)):
            if day(x) in series: series[day(x)]['rentals']+=1
    return {'days':list(series.values())}

@app.get('/api/admin/audit')
def admin_audit(q:str='',limit:int=100,offset:int=0,u=Depends(admin)):
    limit=max(1,min(limit,500))
    with Session() as s:
        stmt=select(Audit).order_by(Audit.created.desc())
        if q: stmt=stmt.where(Audit.action.contains(q)|Audit.actor.contains(q)|Audit.target.contains(q))
        rows=s.scalars(stmt.offset(max(0,offset)).limit(limit)).all()
        return {'items':[{'id':a.id,'action':a.action,'actor':a.actor,'target':a.target,'created':a.created} for a in rows],'more':len(rows)==limit}

@app.get('/api/admin/export/{kind}.csv')
def admin_export(kind:str,u=Depends(admin)):
    import csv
    queries={'users':(User,['id','email','name','role','balance','blocked','max_tabs','created','last_login']),
             'orders':(Order,['id','user_id','code','amount','status','created']),
             'ledger':(Ledger,['id','user_id','amount','description','created']),
             'tabs':(Tab,['id','user_id','name','game','plan','screen','desired','status','expires','created'])}
    if kind not in queries: raise HTTPException(404,'Không có bảng này.')
    model,cols=queries[kind];buf=io.StringIO();w=csv.writer(buf);w.writerow(cols)
    with Session() as s:
        for x in s.scalars(select(model)): w.writerow([getattr(x,c) for c in cols])
    with tx() as s: audit(s,u.id,'export.'+kind,kind)
    return Response('\ufeff'+buf.getvalue(),media_type='text/csv; charset=utf-8',headers={'Content-Disposition':f'attachment; filename="thuetab-{kind}.csv"'})
class FaqItem(BaseModel):
    q: str = Field(min_length=1,max_length=200)
    a: str = Field(min_length=1,max_length=1000)
class TextItem(BaseModel):
    title: str = Field(min_length=1,max_length=80)
    text: str = Field(min_length=1,max_length=300)
class SiteContent(BaseModel):
    announcement: str = Field(default='',max_length=300)
    hero_title: str = Field(min_length=1,max_length=120)
    hero_subtitle: str = Field(min_length=1,max_length=400)
    cta: str = Field(min_length=1,max_length=40)
    features: list[TextItem] = Field(max_length=8)
    steps: list[TextItem] = Field(max_length=6)
    faq: list[FaqItem] = Field(max_length=20)
    footer: str = Field(default='',max_length=200)
class PlanItem(BaseModel):
    id: str = Field(pattern=r'^[a-z0-9_-]{2,20}$')
    name: str = Field(min_length=1,max_length=40)
    days: int = Field(ge=1,le=365)
    price: int = Field(ge=0,le=10_000_000)
    badge: str = Field(default='',max_length=24)
    active: bool = True
class Support(BaseModel):
    zalo: str = Field(default='',max_length=120)
    telegram: str = Field(default='',max_length=120)
    facebook: str = Field(default='',max_length=200)
    email: str = Field(default='',max_length=120)
    hotline: str = Field(default='',max_length=30)
SETTING_MODELS={'site':SiteContent,'support':Support}
@app.get('/api/admin/settings')
def get_settings(u=Depends(admin)):
    return {'referral':features.referral(),'maintenance':features.maintenance(),
            'site':{**SITE_DEFAULTS,**setting('site',{})},'support':{**SUPPORT,**setting('support',{})},
            'plans':setting('plans',DEFAULT_PLANS),'topup_presets':setting('topup_presets',[20000,50000,100000,200000,500000])}
@app.put('/api/admin/settings/{key}')
def put_setting(key:str,b:dict|list=Body(...),u=Depends(admin)):
    try:
        if key in SETTING_MODELS: value=SETTING_MODELS[key](**b).model_dump()
        elif key=='referral': value=features.ReferralIn(**b).model_dump()
        elif key=='maintenance': value=features.MaintenanceIn(**b).model_dump()
        elif key=='plans':
            value=[PlanItem(**x).model_dump() for x in b]
            if not value or len({x['id'] for x in value})!=len(value) or not any(x['active'] for x in value): raise ValueError
        elif key=='topup_presets':
            value=sorted({int(x) for x in b})
            if not 1<=len(value)<=8 or any(not 10000<=x<=5000000 for x in value): raise ValueError
        else: raise HTTPException(404,'Không có mục cài đặt này.')
    except HTTPException: raise
    except Exception: raise HTTPException(422,'Dữ liệu cài đặt không hợp lệ.')
    with tx() as s:
        row=lock(s,Setting,key)
        if row: row.value=json.dumps(value,ensure_ascii=False)
        else: s.add(Setting(key=key,value=json.dumps(value,ensure_ascii=False)))
        audit(s,u.id,'settings.'+key,key)
    return value
class Adjust(BaseModel):
    amount: int = Field(ge=-5000000,le=5000000)
    reason: str = Field(min_length=3,max_length=120)
@app.post('/api/admin/users/{id}/balance')
def adjust_balance(id:str,b:Adjust,u=Depends(admin)):
    if b.amount==0: raise HTTPException(422,'Số tiền phải khác 0.')
    with tx() as s:
        x=lock(s,User,id)
        if not x: raise HTTPException(404,'Không tìm thấy người dùng.')
        if x.balance+b.amount<0: raise HTTPException(409,'Số dư không thể âm.')
        x.balance+=b.amount
        s.add(Ledger(id=uid(),user_id=id,amount=b.amount,description='Điều chỉnh: '+b.reason.strip()))
        audit(s,u.id,'wallet.adjust',f'{id}:{b.amount}')
        return public_user(x)
class Reconcile(BaseModel): reference: str = Field(min_length=3,max_length=100)
@app.post('/api/admin/orders/{id}/confirm')
def confirm_order(id:str,b:Reconcile,u=Depends(admin)):
    # Manual match for a transfer that the webhook could not pair (wrong content, typo in code...).
    with tx() as s:
        o=s.scalar(select(Order).where(Order.id==id).with_for_update())
        if not o or o.status=='paid': raise HTTPException(404,'Đơn không tồn tại hoặc đã thanh toán.')
        ref='MANUAL:'+b.reference.strip()
        if s.scalar(select(Payment).where(Payment.reference==ref)): raise HTTPException(409,'Mã giao dịch này đã được dùng.')
        owner=lock(s,User,o.user_id)
        s.add(Payment(id='MANUAL_'+uid(),reference=ref,order_id=o.id,amount=o.amount))
        owner.balance+=o.amount;o.status='paid'
        s.add(Ledger(id=uid(),user_id=owner.id,amount=o.amount,description='Nạp tiền (admin xác nhận) '+o.code))
        s.flush();features.on_payment(s,o,owner)
        audit(s,u.id,'payment.manual',o.id)
        return order_info(o)
class Extend(BaseModel): hours: int = Field(ge=1,le=24*90)
@app.post('/api/admin/tabs/{id}/extend')
def extend_tab(id:str,b:Extend,u=Depends(admin)):
    with tx() as s:
        t=lock(s,Tab,id)
        if not t: raise HTTPException(404,'Không tìm thấy tab.')
        t.expires=max(now(),t.expires)+b.hours*3600;t.notified_expiry=0
        features.notify(s,t.user_id,f'Bạn được tặng {b.hours} giờ',f'Tab "{t.name}" đã được cộng thêm thời gian.',f'/tabs/{t.id}')
        slot=lock(s,Slot,t.slot_id) if t.slot_id else None
        if slot: slot.expires=t.expires
        audit(s,u.id,'tab.extend',f'{id}:{b.hours}h')
        return internal_tab(t)
@app.get('/api/admin/jars/{id}/download')
def download_jar(id:str,u=Depends(admin)):
    with Session() as s: j=s.get(CustomJar,id)
    if not j or not (JAR_DIR/f'{id}.jar').is_file(): raise HTTPException(404,'Không tìm thấy file JAR.')
    return FileResponse(JAR_DIR/f'{id}.jar',media_type='application/java-archive',filename=re.sub(r'[^\w.-]','_',j.filename))
class JarReview(BaseModel):
    status: str = Field(pattern='^(approved|rejected)$')
@app.patch('/api/admin/jars/{id}')
def review_jar(id:str,b:JarReview,u=Depends(admin)):
    with tx() as s:
        j=lock(s,CustomJar,id)
        if not j: raise HTTPException(404,'Không tìm thấy file JAR.')
        j.status=b.status
        if b.status=='rejected': s.execute(update(Tab).where(Tab.custom_jar_id==id).values(desired='stopped'))
        audit(s,u.id,'jar.'+b.status,id)
        return jar_dict(j)
class WorkerEdit(BaseModel):
    capacity:int=Field(ge=1,le=100)
    draining:bool=False
@app.patch('/api/admin/workers/{id}')
def edit_worker(id:str,b:WorkerEdit,u=Depends(admin)):
    with tx() as s:
        w=lock(s,Worker,id)
        if not w: raise HTTPException(404,'Không tìm thấy worker.')
        w.capacity=b.capacity;w.draining=int(b.draining);audit(s,u.id,'worker.update',id)
    return {'ok':True}
RENEW_WINDOW=3600
def auto_renew(s,t):
    # Opt-in only: charge the tab's plan from the wallet in the last hour before expiry.
    if not t.auto_renew or t.expires<=now() or t.expires-now()>RENEW_WINDOW: return
    p=next((p for p in plans() if p['id']==t.plan),None)
    owner=lock(s,User,t.user_id)
    if not p or not owner or owner.blocked or owner.balance<p['price']:
        t.auto_renew=0; audit(s,'system','tab.auto_renew_failed',t.id)
        if owner: features.notify(s,owner.id,f'Không tự gia hạn được "{t.name}"','Số dư không đủ. Nạp thêm rồi gia hạn thủ công.','/wallet')
        return
    owner.balance-=p['price'];t.expires+=p['days']*86400;t.notified_expiry=0
    features.notify(s,owner.id,f'Đã tự gia hạn "{t.name}"',f"Trừ {p['price']:,}đ, thêm {p['days']} ngày.".replace(',','.'),f'/tabs/{t.id}')
    slot=lock(s,Slot,t.slot_id) if t.slot_id else None
    if slot: slot.expires=t.expires
    s.add(Ledger(id=uid(),user_id=owner.id,amount=-p['price'],description='Tự động gia hạn '+t.name));audit(s,'system','tab.auto_renew',t.id)
class Report(BaseModel):
    id: str = Field(max_length=40)
    memory_mb: int = Field(ge=0)
    system: dict = Field(default_factory=dict)  # host CPU/RAM/disk/network + per-tab figures (admin view)
    statuses: dict[str,str] = Field(default_factory=dict,max_length=100)
@app.post('/api/internal/heartbeat',dependencies=[Depends(worker_auth)])
def heartbeat(b:Report):
    with tx() as s:
        w=lock(s,Worker,b.id)
        if not w: raise HTTPException(403,'Worker not provisioned')
        w.last_seen=now();w.memory_mb=b.memory_mb
        if b.system and len(json.dumps(b.system))<=50000: SYSTEM[b.id]=b.system
        all_tabs=s.scalars(select(Tab).where(Tab.worker_id==b.id)).all()
        for t in all_tabs: auto_renew(s,t)
        commands=[]
        for t in all_tabs:
            owner=s.get(User,t.user_id)
            jar=s.get(CustomJar,t.custom_jar_id) if t.custom_jar_id else None
            if t.expires<=now() or not owner or owner.blocked or (t.custom_jar_id and (not jar or jar.status!='approved')): t.desired='stopped'
            features.on_heartbeat(s,t,owner)
            status=b.statuses.get(t.id)
            if status in ('running','stopped','error','queued'): t.status=status
            if t.expires<=now(): t.status='expired'
        for t in all_tabs:
            if not t.game and t.expires>now(): t.status='idle'
        live=[t for t in all_tabs if t.expires>now() and t.game]
        jars={j.id:j for j in s.scalars(select(CustomJar).where(CustomJar.id.in_([t.custom_jar_id for t in live if t.custom_jar_id])))}
        ids=[t.id for t in live if t.desired=='running']
        if ids:
            for c in s.scalars(select(Command).where(Command.tab_id.in_(ids)).order_by(Command.created).limit(200)):
                if c.created>now()-10: commands.append({'tab_id':c.tab_id,'key':c.key,'text':c.text})
                s.delete(c)
        s.execute(delete(Command).where(Command.created<now()-10))
        s.execute(delete(AuthSession).where(AuthSession.expires<now()))
        s.execute(delete(Rate).where(Rate.reset<now()-3600))
        def runtime(t):
            j=jars.get(t.custom_jar_id)
            return {**internal_tab(t),'kind':j.kind if j else next((g.get('runtime','jar') for g in CATALOG if g['id']==t.game),'jar'),'midlet':j.midlet if j else ''}
        watch=hub.watch()
        return {'tabs':[runtime(t) for t in live], 'commands':commands, 'lease_seconds':15, 'watch':{k:v for k,v in watch.items() if k in ids},'video':[k for k in hub.video() if k in ids],
                'logs':[k for k in hub.logs_wanted() if k in ids],'thumbs':[k for k in hub.thumbs_wanted() if k in ids]}
@app.put('/api/internal/frames/{id}',dependencies=[Depends(worker_auth)])
async def put_frame(id:str,req:Request):
    if not re.fullmatch('[a-f0-9]{24}',id): raise HTTPException(422,'Invalid id')
    with Session() as s:
        t=s.get(Tab,id)
        if not t or t.expires<=now(): raise HTTPException(404,'Inactive tab')
    data=await req.body()
    if len(data)>500000: raise HTTPException(413,'Frame too large')
    if data[:3]==b'\xff\xd8\xff':
        # JPEG snapshot for thumbnails while the tab streams H.264 (held in memory, served by /frame).
        try:
            im=Image.open(io.BytesIO(data))
            if im.format!='JPEG' or im.width>1024 or im.height>1024: raise ValueError()
        except Exception: raise HTTPException(422,'Invalid JPEG')
        hub.set_thumb(id,data)
        return {'ok':True}
    try:
        im=Image.open(io.BytesIO(data))
        if im.format!='PNG' or im.width>1024 or im.height>1024: raise ValueError()
        im.verify()
    except Exception: raise HTTPException(422,'Invalid PNG')
    temp=FRAME_DIR/(id+'.tmp');temp.write_bytes(data);temp.replace(FRAME_DIR/(id+'.png'))
    return {'ok':True}

REDACT=[(re.compile(r'\b\d{1,3}(\.\d{1,3}){3}(:\d+)?\b'),'[ip]'),(re.compile(r'\b[0-9a-f]{12,64}\b'),'[id]'),(re.compile(r'(/opt|/tmp|/home|/usr|/var|/proc)/[^\s:)]*'),'[path]')]
@app.put('/api/internal/logs/{id}',dependencies=[Depends(worker_auth)])
async def put_logs(id:str,req:Request):
    if not re.fullmatch('[a-f0-9]{24}',id): raise HTTPException(422,'Invalid id')
    text=(await req.body())[-16000:].decode('utf-8','replace')
    # Hide addresses, container ids and filesystem layout from users.
    for pattern,repl in REDACT: text=pattern.sub(repl,text)
    (LOG_DIR/(id+'.txt')).write_text(text)
    return {'ok':True}

from . import features
app.include_router(features.router)

DIST=ROOT/'web/dist'
if DIST.exists():
    app.mount('/assets', StaticFiles(directory=DIST/'assets'), name='assets')
    if (DIST/'icons').exists():
        app.mount('/icons', StaticFiles(directory=DIST/'icons'), name='icons')
    
    @app.get('/logo.svg')
    def get_logo(): return FileResponse(DIST/'logo.svg')

    @app.get('/logo.png')
    def get_logo_png(): return FileResponse(DIST/'logo.png')

    @app.get('/favicon.svg')
    def icon(): return FileResponse(DIST/'favicon.svg')

    @app.get('/{full_path:path}')
    def spa_fallback(full_path: str):
        if full_path.startswith('api/'): raise HTTPException(404,'Không tìm thấy.')
        if full_path:
            target = (DIST / full_path).resolve()
            if target.is_relative_to(DIST.resolve()) and target.is_file() and not target.name.endswith('.import'):
                return FileResponse(target)
        return FileResponse(DIST / 'index.html')
else:
    # API-only server (web on Cloudflare Pages): links opened on the API host — e.g. share/referral links from
    # app 1.2.0, https://<api>/#/s/TOKEN — are sent to the web front-end. The #fragment never reaches the
    # server, so the page forwards it in the browser.
    REDIRECT_PAGE=('<!doctype html><meta charset="utf-8"><meta name="robots" content="noindex"><title>ThuêTab</title>'
                   '<script>var w=%s;if(w.indexOf(location.origin)!==0)location.replace(w+location.pathname+location.search+location.hash);'
                   'else document.write("ThuêTab");</script><noscript><a href="%s">ThuêTab</a></noscript>')
    @app.get('/{full_path:path}',include_in_schema=False)
    def to_web(full_path: str):
        if full_path.startswith('api/'): raise HTTPException(404,'Không tìm thấy.')
        web=ORIGINS[0]
        return Response(REDIRECT_PAGE%(json.dumps(web),web),media_type='text/html',headers={'Cache-Control':'no-store'})
