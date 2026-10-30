import os, tempfile
os.environ['DATABASE_URL']='sqlite:///'+tempfile.mktemp(suffix='.sqlite')
os.environ['DATA_DIR']=tempfile.mkdtemp(prefix='thuetab-test-')
os.environ['WORKER_TOKEN']='test-worker-secret-00000000000000000000000'
os.environ['SEPAY_API_KEY']='test-sepay-secret-000000000000000000000000'
os.environ['BANK_ACCOUNT']='123456789'
os.environ['BANK_NAME']='Vietcombank'
os.environ['BANK_CODE']='VCB'
os.environ['JAR_AUTO_APPROVE']='false'
import pytest, io, zipfile, json
def make_jar(manifest='Manifest-Version: 1.0\nMIDlet-1: Ninja,/icon.png,game.Main\nMIDlet-Name: Ninja\n'):
    buf=io.BytesIO()
    with zipfile.ZipFile(buf,'w') as z: z.writestr('META-INF/MANIFEST.MF',manifest);z.writestr('game/Main.class',b'\xca\xfe')
    return buf.getvalue()
from concurrent.futures import ThreadPoolExecutor
from fastapi.testclient import TestClient
from sqlalchemy import select
from backend.app import app, tx, now, uid, ph, CATALOG
# The bundled sample game is hidden in production; tests use it as a runnable fixture.
next(g for g in CATALOG if g['id']=='java-demo')['enabled']=True
from backend.db import Base,engine,User,Worker,Tab,Slot,Session,Payment,Order

@pytest.fixture(autouse=True)
def reset():
    Base.metadata.drop_all(engine);Base.metadata.create_all(engine)
    with tx() as s:
        s.add(Worker(id='local-1',capacity=4,last_seen=now()))
        s.add(User(id='admin',email='admin@test.vn',name='Admin',password=ph.hash('password1234'),role='admin',balance=100000,trial_approved=1))
        s.add(User(id='alice',email='alice@test.vn',name='Alice',password=ph.hash('password1234'),balance=100000,trial_approved=1))
        s.add(User(id='bob',email='bob@test.vn',name='Bob',password=ph.hash('password1234'),balance=100000))

def client(email='alice@test.vn'):
    c=TestClient(app)
    r=c.post('/api/auth/login',json={'email':email,'password':'password1234'})
    assert r.status_code==200,r.text
    c.cookies.clear();c.headers['Authorization']='Bearer '+r.json()['token']
    return c

def rent(c,**kwargs): return c.post('/api/tabs',json={'name':'Tab test','game':'java-demo','plan':'month',**kwargs})

def test_ownership_and_admin():
    a=client();b=client('bob@test.vn');ad=client('admin@test.vn')
    tab=rent(a).json()
    assert b.patch('/api/tabs/'+tab['id'],json={'name':'hacked'}).status_code==404
    assert b.get('/api/tabs/'+tab['id']+'/frame').status_code==404
    assert b.get('/api/admin/overview').status_code==403
    assert ad.get('/api/admin/overview').status_code==200

def test_capacity_and_no_charge_on_rejection():
    c=client()
    for i in range(4): assert rent(c,name=str(i)).status_code==201
    before=c.get('/api/me').json()['balance']
    assert rent(c).status_code==409
    assert c.get('/api/me').json()['balance']==before

def test_trial_once_and_requires_approval():
    a=client();b=client('bob@test.vn')
    assert rent(b,trial=True).status_code==403
    assert rent(a,trial=True).status_code==201
    assert rent(a,trial=True).status_code==403
    assert a.get('/api/me').json()['balance']==100000

def test_sepay_duplicate_and_amount_validation():
    c=client();order=c.post('/api/wallet/orders',json={'amount':50000}).json()
    b={'id':1234,'accountNumber':'123456789','gateway':'Vietcombank','referenceCode':'FT001','transferType':'in','transferAmount':50000,'content':order['code']}
    webhook=TestClient(app);headers={'Authorization':'Apikey '+os.environ['SEPAY_API_KEY']}
    assert webhook.post('/api/payments/sepay',json=b).status_code==401
    # Not creditable: acknowledged so SePay doesn't retry, nothing credited, logged for manual reconciliation.
    r=webhook.post('/api/payments/sepay',headers=headers,json={**b,'transferAmount':49000})
    assert r.status_code==200 and r.json()['matched'] is False
    assert webhook.post('/api/payments/sepay',headers=headers,json={**b,'accountNumber':'wrong'}).json()['matched'] is False
    assert c.get('/api/me').json()['balance']==100000
    assert any(x['action']=='payment.unmatched' for x in client('admin@test.vn').get('/api/admin/audit?q=unmatched').json()['items'])
    with ThreadPoolExecutor(max_workers=6) as pool:
        replies=list(pool.map(lambda _:webhook.post('/api/payments/sepay',headers=headers,json=b),range(6)))
    assert all(r.status_code==200 for r in replies)
    assert c.get('/api/me').json()['balance']==150000
    assert webhook.post('/api/payments/sepay',headers=headers,json={**b,'id':1235}).json()['duplicate']
    assert c.get('/api/me').json()['balance']==150000

def test_concurrent_slot_capacity_and_atomic_purchase():
    c=client()
    with ThreadPoolExecutor(max_workers=6) as pool:
        replies=list(pool.map(lambda _:c.post('/api/slots',json={'quantity':1,'plan':'month'}),range(6)))
    assert sum(r.status_code==201 for r in replies)==4
    assert c.get('/api/me').json()['balance']==64000
    assert len(c.get('/api/slots').json())==4

def test_buy_attach_release_slot_no_second_charge():
    c=client()
    slot=c.post('/api/slots',json={'quantity':1,'plan':'month'}).json()[0]
    before=c.get('/api/me').json()['balance']
    t=rent(c,slot_id=slot['id']).json()
    assert c.get('/api/me').json()['balance']==before
    assert rent(c,slot_id=slot['id']).status_code==409
    assert c.delete('/api/tabs/'+t['id']).status_code==409
    c.patch('/api/tabs/'+t['id'],json={'desired':'stopped'})
    worker=TestClient(app)
    worker.post('/api/internal/heartbeat',headers={'Authorization':'Bearer '+os.environ['WORKER_TOKEN']},json={'id':'local-1','memory_mb':0,'statuses':{t['id']:'stopped'}})
    assert c.delete('/api/tabs/'+t['id']).status_code==200
    assert rent(c,slot_id=slot['id']).status_code==201
    assert c.get('/api/me').json()['balance']==before

def test_block_revokes_sessions_and_stops_tabs():
    c=client();a=client('admin@test.vn');t=rent(c).json()
    assert a.patch('/api/admin/users/alice',json={'blocked':True}).status_code==200
    assert c.get('/api/me').status_code==401
    with Session() as s: assert s.get(Tab,t['id']).desired=='stopped'

def test_worker_expiry_auth_and_input():
    c=client();t=rent(c).json()
    assert c.post('/api/tabs/'+t['id']+'/input',json={'key':'$(touch /tmp/hacked)'}).status_code==422
    with tx() as s: s.get(Tab,t['id']).expires=now()-1
    w=TestClient(app)
    data={'id':'local-1','memory_mb':0,'statuses':{}}
    assert w.post('/api/internal/heartbeat',json=data).status_code==401
    r=w.post('/api/internal/heartbeat',headers={'Authorization':'Bearer '+os.environ['WORKER_TOKEN']},json=data)
    assert r.status_code==200 and not r.json()['tabs']
    assert c.post('/api/tabs/'+t['id']+'/input',json={'key':'Up'}).status_code==409

def test_cookie_csrf_and_logout():
    c=TestClient(app)
    assert c.post('/api/auth/login',json={'email':'alice@test.vn','password':'password1234'}).status_code==200
    assert c.post('/api/slots',json={'quantity':1}).status_code==403
    assert c.post('/api/slots',headers={'Origin':'https://evil.example'},json={'quantity':1}).status_code==403
    assert c.post('/api/auth/logout',headers={'Origin':'http://127.0.0.1:8000'}).status_code==200
    assert c.get('/api/me').status_code==401

def test_insufficient_wallet_and_disabled_game():
    c=client()
    with tx() as s: s.get(User,'alice').balance=0
    assert rent(c).status_code==409
    assert rent(c,game='j2me',trial=True).status_code==422

def test_renew_expired_requires_capacity():
    c=client();t=rent(c).json()
    with tx() as s:
        s.get(Tab,t['id']).expires=now()-1;s.get(Slot,t['slot_id']).expires=now()-1
    assert c.post('/api/slots',json={'quantity':4,'plan':'month'}).status_code==201
    before=c.get('/api/me').json()['balance']
    assert c.post('/api/tabs/'+t['id']+'/renew',json={'plan':'month'}).status_code==409
    assert c.get('/api/me').json()['balance']==before

def test_custom_jar_upload_and_rent():
    c=client()
    # Invalid upload without zip header
    bad_res = c.post('/api/jars/upload', headers={'X-Filename': 'mod.jar'}, content=b'invalid raw binary')
    assert bad_res.status_code == 422
    # Valid jar upload with PK\x03\x04 header
    good_jar = make_jar()
    up = c.post('/api/jars/upload', headers={'X-Filename': 'nso_mod_v12.jar'}, content=good_jar)
    assert up.status_code == 200
    jar_id = up.json()['jar']['id']
    # List jars
    lst = c.get('/api/jars').json()
    assert any(j['id'] == jar_id for j in lst)
    assert lst[0]['status'] == 'pending' and len(lst[0]['sha256']) == 64
    with tx() as s: s.get(User, 'alice').balance = 50000
    # Unreviewed code must not run
    blocked = c.post('/api/tabs', json={'name': 'Tab Mod Rieng', 'game': 'custom-jar', 'custom_jar_id': jar_id, 'plan': 'day'})
    assert blocked.status_code == 409
    assert c.patch('/api/admin/jars/'+jar_id, json={'status':'approved'}).status_code == 403
    assert client('admin@test.vn').patch('/api/admin/jars/'+jar_id, json={'status':'approved'}).status_code == 200
    # Rent tab with custom jar
    t = c.post('/api/tabs', json={'name': 'Tab Mod Rieng', 'game': 'custom-jar', 'custom_jar_id': jar_id, 'plan': 'day'}).json()
    assert t['custom_jar_id'] == jar_id
    assert t['game'] == 'custom-jar'

def test_no_simulated_topup_endpoint():
    c=client()
    o=c.post('/api/wallet/orders',json={'amount':20000}).json()
    assert 'can_simulate' not in o and o['qr_url'].startswith('https://qr.sepay.vn/')
    assert c.post('/api/wallet/orders/'+o['id']+'/simulate').status_code in (404,405)

def test_public_config_and_status_are_real():
    c=TestClient(app)
    cfg=c.get('/api/config').json()
    assert cfg['is_live_payment'] is True
    for k in ('dev_mode','version','memory_mb','cpu'): assert k not in cfg
    assert {'java-demo','custom-jar'}>={g['id'] for g in cfg['games']}
    st=c.get('/api/status').json()
    assert st['online'] and st['accepting'] and set(st)=={'online','accepting','time'}

def test_jar_auto_approve(monkeypatch):
    import backend.app as m
    monkeypatch.setattr(m,'JAR_AUTO_APPROVE',True)
    c=client()
    up=c.post('/api/jars/upload',headers={'X-Filename':'game.jar'},content=make_jar('Main-Class: Garden\n')).json()
    assert up['jar']['status']=='approved'
    assert c.post('/api/tabs',json={'name':'t','game':'custom-jar','custom_jar_id':up['jar']['id'],'plan':'day'}).status_code==201

def test_jar_manifest_detection():
    c=client()
    assert c.post('/api/jars/upload',headers={'X-Filename':'x.jar'},content=make_jar('Manifest-Version: 1.0\n')).status_code==422
    assert c.post('/api/jars/upload',headers={'X-Filename':'x.jar'},content=make_jar('MIDlet-1: A,,bad;rm -rf\n')).status_code==422
    j=c.post('/api/jars/upload',headers={'X-Filename':'nso.jar'},content=make_jar()).json()['jar']
    assert j['kind']=='midp' and j['midlet']=='game.Main'

def test_text_sync_input_and_heartbeat_runtime():
    a=client();b=client('bob@test.vn')
    t1=rent(a).json();t2=rent(a).json();tb=rent(b).json()
    assert a.post('/api/tabs/'+t1['id']+'/input',json={'key':'F1'}).status_code==200
    assert a.post('/api/tabs/'+t1['id']+'/text',json={'text':'user123'}).status_code==200
    assert a.post('/api/tabs/'+t1['id']+'/text',json={'text':'có dấu'}).status_code==422
    r=a.post('/api/tabs/input',json={'tab_ids':[t1['id'],t2['id'],tb['id']],'key':'5'}).json()
    assert r['sent']==2
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN']
    hb=w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}}).json()
    assert {'tab_id':t1['id'],'key':'','text':'user123'} in hb['commands']
    assert sum(1 for c in hb['commands'] if c['key']=='5')==2
    assert all(t['kind']=='jar' for t in hb['tabs'])

def test_auto_renew():
    a=client()
    t=rent(a).json()
    assert a.patch('/api/tabs/'+t['id'],json={'auto_renew':True}).json()['auto_renew']==1
    with tx() as s: s.get(Tab,t['id']).expires=now()+60;s.get(Slot,t['slot_id']).expires=now()+60
    before=a.get('/api/me').json()['balance']
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN']
    w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}})
    tab=[x for x in a.get('/api/tabs').json() if x['id']==t['id']][0]
    assert tab['expires']>now()+29*86400
    assert a.get('/api/me').json()['balance']==before-9000
    # not enough money -> auto renew switches itself off, nothing charged
    with tx() as s: s.get(Tab,t['id']).expires=now()+60;s.get(User,'alice').balance=0
    w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}})
    tab=[x for x in a.get('/api/tabs').json() if x['id']==t['id']][0]
    assert tab['auto_renew']==0 and a.get('/api/me').json()['balance']==0

def test_switch_game_and_jar_on_same_tab():
    a=client()
    t=rent(a).json()
    j=a.post('/api/jars/upload',headers={'X-Filename':'nso.jar'},content=make_jar()).json()['jar']
    # JAR uploads are pending here (JAR_AUTO_APPROVE=false in tests)
    assert a.patch('/api/tabs/'+t['id'],json={'game':'custom-jar','custom_jar_id':j['id']}).status_code==409
    client('admin@test.vn').patch('/api/admin/jars/'+j['id'],json={'status':'approved'})
    r=a.patch('/api/tabs/'+t['id'],json={'game':'custom-jar','custom_jar_id':j['id']}).json()
    assert r['game']=='custom-jar' and r['custom_jar_id']==j['id'] and r['status']=='queued'
    assert a.delete('/api/jars/'+j['id']).status_code==409
    assert a.patch('/api/tabs/'+t['id'],json={'game':'nso-java'}).status_code==422
    r=a.patch('/api/tabs/'+t['id'],json={'game':'java-demo'}).json()
    assert r['custom_jar_id'] is None
    assert a.delete('/api/jars/'+j['id']).status_code==200
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN']
    hb=w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}}).json()
    assert hb['tabs'][0]['worker_id']=='local-1'

def test_no_internal_info_leaks():
    a=client()
    t=rent(a).json()
    for x in [t,*a.get('/api/tabs').json(),*a.get('/api/slots').json()]:
        assert 'worker_id' not in x and 'user_id' not in x
    c=TestClient(app)
    assert c.get('/api/docs').status_code==404 and c.get('/api/openapi.json').status_code==404
    assert c.get('/api/nope').status_code==404
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN']
    w.put('/api/internal/logs/'+t['id'],content=b'connect 10.0.0.5:8080 container 3f2a9b1c0d4e5f6a at /opt/game/x.jar')
    logs=a.get('/api/tabs/'+t['id']+'/logs').json()['logs']
    assert '10.0.0.5' not in logs and '3f2a9b1c0d4e' not in logs and '/opt/game' not in logs

def test_account_password_and_sessions():
    a=client();other=client()
    assert a.patch('/api/me',json={'name':'Alice Mới'}).json()['name']=='Alice Mới'
    assert a.post('/api/me/password',json={'old':'wrong','new':'newpassword123'}).status_code==403
    assert a.post('/api/me/password',json={'old':'password1234','new':'newpassword123'}).status_code==200
    assert a.get('/api/me').status_code==200 and other.get('/api/me').status_code==401
    assert TestClient(app).post('/api/auth/login',json={'email':'alice@test.vn','password':'newpassword123'}).status_code==200

def test_admin_tools_and_order_cancel():
    a=client();ad=client('admin@test.vn')
    o=a.post('/api/wallet/orders',json={'amount':50000}).json()
    assert a.delete('/api/wallet/orders/'+o['id']).json()['status']=='cancelled'
    assert a.post('/api/admin/orders/'+o['id']+'/confirm',json={'reference':'FT123'}).status_code==403
    before=a.get('/api/me').json()['balance']
    assert ad.post('/api/admin/orders/'+o['id']+'/confirm',json={'reference':'FT123'}).json()['status']=='paid'
    assert a.get('/api/me').json()['balance']==before+50000
    assert ad.post('/api/admin/users/alice/balance',json={'amount':-10**6,'reason':'test'}).status_code==409
    assert ad.post('/api/admin/users/alice/balance',json={'amount':-5000,'reason':'hoàn tiền sai'}).json()['balance']==before+45000
    t=rent(a).json()
    assert ad.post('/api/admin/tabs/'+t['id']+'/extend',json={'hours':24}).json()['expires']>=t['expires']+86400

def test_sepay_poll_credits_once(monkeypatch):
    import backend.app as m, httpx
    a=client()
    o=a.post('/api/wallet/orders',json={'amount':30000}).json()
    before=a.get('/api/me').json()['balance']
    tx_list={'transactions':[{'id':'99001','amount_in':'30000.00','reference_number':'FT999','transaction_content':'chuyen tien '+o['code'],'code':None},
                             {'id':'99002','amount_in':'0.00','amount_out':'5000','reference_number':'FT1','transaction_content':'x'}]}
    class R:
        def raise_for_status(self): pass
        def json(self): return tx_list
    monkeypatch.setattr(httpx,'get',lambda *a,**k: R())
    assert m.poll_sepay()==1 and m.poll_sepay()==0
    assert a.get('/api/me').json()['balance']==before+30000

def test_tap_and_swipe():
    a=client();t=rent(a).json()
    assert a.post('/api/tabs/'+t['id']+'/tap',json={'x':10,'y':300}).status_code==200
    assert a.post('/api/tabs/'+t['id']+'/tap',json={'x':10,'y':300,'x2':200,'y2':300}).status_code==200
    assert a.post('/api/tabs/'+t['id']+'/tap',json={'x':-1,'y':0}).status_code==422
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN']
    cmds=w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}}).json()['commands']
    assert {'tab_id':t['id'],'key':'@tap','text':'10,300'} in cmds and {'tab_id':t['id'],'key':'@swipe','text':'10,300,200,300'} in cmds

def test_stream_websocket_auth_and_input():
    from starlette.websockets import WebSocketDisconnect
    import backend.app as m
    a=client();b=client('bob@test.vn');tab=rent(a).json()
    tok=a.headers['Authorization'];c=TestClient(app)
    with pytest.raises(WebSocketDisconnect) as e:
        with c.websocket_connect('/api/tabs/'+tab['id']+'/stream',headers={'Authorization':b.headers['Authorization']}) as ws: ws.receive_text()
    assert e.value.code==4404
    with pytest.raises(WebSocketDisconnect) as e:
        with c.websocket_connect('/api/tabs/'+tab['id']+'/stream',headers={'origin':'https://evil.example'}) as ws: ws.receive_text()
    assert e.value.code==4403
    with c.websocket_connect('/api/tabs/'+tab['id']+'/stream?fps=60',headers={'Authorization':tok}) as ws:
        hello=json.loads(ws.receive_text())
        assert hello['type']=='hello' and hello['fps']==60 and hello['width']==640
        assert m.hub.watch()=={tab['id']:60}
        ws.send_text(json.dumps({'type':'ping','t':42}))
        assert json.loads(ws.receive_text())=={'type':'pong','t':42}
        ws.send_text(json.dumps({'type':'key','key':'rm -rf'}))
        assert json.loads(ws.receive_text())['type']=='error'
        ws.send_text(json.dumps({'type':'tap','x':5,'y':6}))
        ws.send_text(json.dumps({'type':'fps','fps':30}))
        ws.send_text(json.dumps({'type':'key','key':'Up'}))
        import time as _t; _t.sleep(0.3)
    assert m.hub.watch()=={}
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN']
    cmds=w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}}).json()['commands']
    assert {'tab_id':tab['id'],'key':'@tap','text':'5,6'} in cmds and {'tab_id':tab['id'],'key':'Up','text':''} in cmds

def test_rent_without_game_then_choose():
    a=client()
    t=a.post('/api/tabs',json={'name':'trống','plan':'day'}).json()
    assert t['game']=='' and t['status']=='idle'
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN']
    hb=w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}}).json()
    assert all(x['id']!=t['id'] for x in hb['tabs'])
    assert [x for x in a.get('/api/tabs').json() if x['id']==t['id']][0]['status']=='idle'
    assert a.patch('/api/tabs/'+t['id'],json={'game':'java-demo'}).json()['game']=='java-demo'
    hb=w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}}).json()
    assert any(x['id']==t['id'] for x in hb['tabs'])

def test_screen_orientation_switch():
    a=client()
    cfg=TestClient(app).get('/api/config').json()
    assert {'240x320','320x240','640x360'}<={x['id'] for x in cfg['screens']}
    j=a.post('/api/jars/upload',headers={'X-Filename':'nro.jar'},content=make_jar('MIDlet-1: NRO,,a.Main\nNokia-MIDlet-Original-Display-Size: 320,240\n')).json()['jar']
    assert j['screen']=='320x240'
    client('admin@test.vn').patch('/api/admin/jars/'+j['id'],json={'status':'approved'})
    t=a.post('/api/tabs',json={'name':'nro','plan':'day','game':'custom-jar','custom_jar_id':j['id']}).json()
    assert t['screen']=='320x240'
    assert a.patch('/api/tabs/'+t['id'],json={'screen':'999x1'}).status_code==422
    r=a.patch('/api/tabs/'+t['id'],json={'screen':'640x360'}).json()
    assert r['screen']=='640x360' and r['status']=='queued'
    with TestClient(app).websocket_connect('/api/tabs/'+t['id']+'/stream',headers={'Authorization':a.headers['Authorization']}) as ws:
        hello=json.loads(ws.receive_text())
        assert (hello['kind'],hello['width'],hello['height'])==('midp',640,360)
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN']
    hb=w.post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}}).json()
    assert [x['screen'] for x in hb['tabs'] if x['id']==t['id']]==['640x360']

def test_manifestless_midlet_detected():
    import struct
    def utf8(s): b=s.encode(); return b'\x01'+struct.pack('>H',len(b))+b
    cls=(b'\xca\xfe\xba\xbe'+struct.pack('>HHH',0,46,5)+b'\x07\x00\x02'+utf8('game/Main')+b'\x07\x00\x04'+utf8('javax/microedition/midlet/MIDlet')
         +struct.pack('>HHHHHHH',0x21,1,3,0,0,0,0))
    buf=io.BytesIO()
    with zipfile.ZipFile(buf,'w') as z: z.writestr('game/Main.class',cls);z.writestr('a.class',b'\xca\xfe')
    j=client().post('/api/jars/upload',headers={'X-Filename':'nro.jar'},content=buf.getvalue()).json()['jar']
    assert (j['kind'],j['midlet'])==('midp','game.Main')

def test_admin_settings_and_user_prefs():
    a=client();ad=client('admin@test.vn');c=TestClient(app)
    assert a.put('/api/admin/settings/site',json={}).status_code==403
    site=c.get('/api/config').json()['site'];site['hero_title']='Tiêu đề mới';site['announcement']='Bảo trì 22h'
    assert ad.put('/api/admin/settings/site',json=site).status_code==200
    cfg=c.get('/api/config').json()
    assert cfg['site']['hero_title']=='Tiêu đề mới' and cfg['site']['announcement']=='Bảo trì 22h'
    plans=[{'id':'day','name':'Ngày','days':1,'price':2000},{'id':'month','name':'Tháng','days':30,'price':30000,'badge':'Phổ biến'},{'id':'old','name':'Cũ','days':7,'price':1,'active':False}]
    assert ad.put('/api/admin/settings/plans',json=plans).status_code==200
    assert [p['id'] for p in c.get('/api/config').json()['plans']]==['day','month']
    assert ad.put('/api/admin/settings/plans',json=[{'id':'x','name':'y','days':1,'price':1,'active':False}]).status_code==422
    t=a.post('/api/tabs',json={'name':'p','plan':'month'}).json()
    assert a.get('/api/wallet').json()['ledger'][0]['amount']==-30000
    assert ad.put('/api/admin/settings/support',json={'zalo':'0900','email':'hotro@example.com'}).status_code==200
    assert c.get('/api/config').json()['support']['zalo']=='0900'
    assert ad.put('/api/admin/settings/nope',json={}).status_code==404
    me=a.get('/api/me').json()
    assert me['prefs']['theme']=='dark' and me['prefs']['default_fps']==30
    r=a.patch('/api/me/prefs',json={'theme':'light','default_fps':60,'default_screen':'640x360','haptics':False}).json()
    assert r['prefs']['theme']=='light' and r['prefs']['default_screen']=='640x360' and r['prefs']['haptics'] is False
    assert a.patch('/api/me/prefs',json={'theme':'pink'}).status_code==422
    assert a.patch('/api/me/prefs',json={'hack':1}).status_code==422
    assert a.patch('/api/me/prefs',json={'default_fps':True}).status_code==422

def test_downloads_listing(tmp_path):
    import backend.app as m
    d=m.DATA_DIR/'downloads';d.mkdir(exist_ok=True)
    (d/'ThueTab-Windows.exe').write_bytes(b'MZ'+b'\0'*10);(d/'ThueTab-Android.apk').write_bytes(b'PK')
    dl={x['platform']:x for x in TestClient(app).get('/api/config').json()['downloads']}
    assert set(dl)=={'windows','android'} and dl['windows']['url']=='/api/downloads/ThueTab-Windows.exe'
    assert TestClient(app).get('/api/downloads/ThueTab-Windows.exe').content.startswith(b'MZ')
    assert TestClient(app).get('/api/downloads/..%2F..%2Fbackend%2Fapp.py').status_code==404

def test_admin_user_management():
    ad=client('admin@test.vn');a=client();c=TestClient(app)
    tab=rent(a).json()
    d=ad.get('/api/admin/users/alice').json()
    assert d['user']['tabs']==1 and len(d['tabs'])==1 and d['ledger']
    assert a.get('/api/admin/users/alice').status_code==403
    r=ad.patch('/api/admin/users/alice',json={'name':'Alice B','max_tabs':1,'note':'VIP'}).json()
    assert r['name']=='Alice B' and r['max_tabs']==1
    assert rent(a).status_code==409
    assert ad.patch('/api/admin/users/bob',json={'email':'alice@test.vn'}).status_code==409
    assert ad.patch('/api/admin/users/admin',json={'role':'user'}).status_code==409
    assert ad.delete('/api/admin/users/admin').status_code==409
    pw=ad.post('/api/admin/users/alice/password').json()['password']
    assert a.get('/api/me').status_code==401
    assert c.post('/api/auth/login',json={'email':'alice@test.vn','password':pw}).status_code==200
    assert ad.post('/api/admin/users/alice/logout').json()['sessions']>=1
    assert ad.delete('/api/admin/tabs/'+tab['id']).status_code==200
    assert ad.delete('/api/admin/users/alice').status_code==200
    assert ad.get('/api/admin/users/alice').status_code==404
    assert TestClient(app).post('/api/auth/login',json={'email':'alice@test.vn','password':pw}).status_code==401

def test_admin_ops_tools():
    ad=client('admin@test.vn');b=client('bob@test.vn')
    j=b.post('/api/jars/upload',headers={'X-Filename':'g.jar'},content=make_jar()).json()['jar']
    ad.patch('/api/admin/jars/'+j['id'],json={'status':'approved'})
    t=b.post('/api/tabs',json={'name':'x','plan':'day','game':'custom-jar','custom_jar_id':j['id']}).json()
    assert ad.delete('/api/admin/jars/'+j['id']).status_code==200
    tb=[x for x in b.get('/api/tabs').json() if x['id']==t['id']][0]
    assert tb['game']=='' and tb['custom_jar_id'] is None
    o=b.post('/api/wallet/orders',json={'amount':10000}).json()
    assert ad.post('/api/admin/orders/'+o['id']+'/cancel').json()['status']=='cancelled'
    assert ad.post('/api/admin/workers',json={'id':'node-2','capacity':3}).status_code==201
    assert ad.delete('/api/admin/workers/node-2').status_code==200
    assert ad.delete('/api/admin/workers/local-1').status_code==409
    st=ad.get('/api/admin/stats?days=7').json()['days']
    assert len(st)==7 and sum(x['rentals'] for x in st)>=1 and sum(x['spend'] for x in st)>=1500
    assert any(x['action']=='order.cancel' for x in ad.get('/api/admin/audit?q=order').json()['items'])
    csv=ad.get('/api/admin/export/users.csv')
    assert csv.status_code==200 and 'bob@test.vn' in csv.text and b.get('/api/admin/export/users.csv').status_code==403

def _worker():
    w=TestClient(app);w.headers['Authorization']='Bearer '+os.environ['WORKER_TOKEN'];return w
def _hb(): return _worker().post('/api/internal/heartbeat',json={'id':'local-1','memory_mb':0,'statuses':{}}).json()

def test_coupons_rent_and_topup():
    ad=client('admin@test.vn');a=client()
    assert ad.post('/api/admin/coupons',json={'code':'giam50','kind':'percent','value':50,'max_uses':1}).status_code==201
    assert ad.post('/api/admin/coupons',json={'code':'NAP20','kind':'topup','value':20,'max_value':5000}).status_code==201
    assert a.post('/api/admin/coupons',json={'code':'X1Y','kind':'amount','value':1}).status_code==403
    q=a.post('/api/coupons/check',json={'code':'GIAM50','context':'rent','amount':9000}).json()
    assert q['discount']==4500 and q['final']==4500
    assert a.post('/api/coupons/check',json={'code':'NAP20','context':'rent','amount':9000}).status_code==422
    before=a.get('/api/me').json()['balance']
    assert rent(a,coupon='GIAM50').status_code==201
    assert a.get('/api/me').json()['balance']==before-4500
    assert rent(a,coupon='GIAM50').status_code==422          # max_uses reached
    o=a.post('/api/wallet/orders',json={'amount':50000,'coupon':'NAP20'}).json()
    assert o['coupon']=='NAP20'
    bal=a.get('/api/me').json()['balance']
    ad.post('/api/admin/orders/'+o['id']+'/confirm',json={'reference':'FTX1'})
    assert a.get('/api/me').json()['balance']==bal+50000+5000   # 20% capped at 5000
    assert any(n['title']=='Nạp tiền thành công' for n in a.get('/api/notifications').json()['items'])
    uses=ad.get('/api/admin/coupons').json()['uses']
    assert {u['code'] for u in uses}=={'GIAM50','NAP20'}

def test_referral_reward_on_first_topup():
    ad=client('admin@test.vn');a=client()
    ref=a.get('/api/me/referral').json()
    c=TestClient(app)
    assert c.post('/api/auth/register',json={'email':'new@test.vn','password':'password1234','name':'Bạn mới','ref':ref['code']}).status_code==201
    n=client('new@test.vn')
    o=n.post('/api/wallet/orders',json={'amount':100000}).json()
    before=a.get('/api/me').json()['balance']
    ad.post('/api/admin/orders/'+o['id']+'/confirm',json={'reference':'FTR1'})
    assert a.get('/api/me').json()['balance']==before+10000
    o2=n.post('/api/wallet/orders',json={'amount':100000}).json()
    ad.post('/api/admin/orders/'+o2['id']+'/confirm',json={'reference':'FTR2'})
    assert a.get('/api/me').json()['balance']==before+10000      # only the first top-up counts
    r=a.get('/api/me/referral').json()
    assert r['invited']==1 and r['earned']==10000

def test_share_link_view_and_control():
    a=client();b=client('bob@test.vn');tab=rent(a).json()
    assert b.post('/api/tabs/'+tab['id']+'/shares',json={}).status_code==404
    view=a.post('/api/tabs/'+tab['id']+'/shares',json={'hours':2,'label':'bạn'}).json()
    ctl=a.post('/api/tabs/'+tab['id']+'/shares',json={'can_control':True}).json()
    pub=TestClient(app).get('/api/share/'+view['token']).json()
    assert pub['name']=='Tab test' and pub['can_control'] is False and 'user_id' not in pub
    c=TestClient(app)
    with c.websocket_connect(f"/api/tabs/{tab['id']}/stream?share={view['token']}") as ws:
        assert json.loads(ws.receive_text())['type']=='hello'
        ws.send_text(json.dumps({'type':'key','key':'5'}))
        assert 'chỉ cho phép xem' in json.loads(ws.receive_text())['detail']
    with c.websocket_connect(f"/api/tabs/{tab['id']}/stream?share={ctl['token']}") as ws:
        ws.receive_text();ws.send_text(json.dumps({'type':'key','key':'7'}));import time as _t;_t.sleep(0.2)
    assert any(x['key']=='7' for x in _hb()['commands'])
    assert a.delete(f"/api/tabs/{tab['id']}/shares/{view['token']}").status_code==200
    assert TestClient(app).get('/api/share/'+view['token']).status_code==404

def test_tickets_and_notifications():
    a=client();ad=client('admin@test.vn')
    t=a.post('/api/tickets',json={'subject':'Game không vào được','body':'Màn hình đen'}).json()
    assert t['status']=='open' and len(t['messages'])==1
    assert client('bob@test.vn').get('/api/tickets/'+t['id']).status_code==404
    assert any(x['id']==t['id'] for x in ad.get('/api/admin/tickets?status=open').json())
    r=ad.post('/api/tickets/'+t['id']+'/messages',json={'body':'Bạn thử khởi động lại tab nhé'}).json()
    assert r['status']=='answered' and r['messages'][-1]['staff'] is True
    notes=a.get('/api/notifications').json()
    assert notes['unread']>=1 and notes['items'][0]['title']=='Hỗ trợ đã trả lời'
    a.post('/api/notifications/read',json={'all':True})
    assert a.get('/api/notifications').json()['unread']==0
    assert ad.post('/api/admin/notifications',json={'title':'Bảo trì tối nay','body':'22h'}).json()['sent']==3
    assert a.post('/api/tickets/'+t['id']+'/close').json()['status']=='closed'

def test_maintenance_blocks_new_rentals():
    a=client();ad=client('admin@test.vn')
    assert ad.put('/api/admin/settings/maintenance',json={'enabled':True,'message':'Nâng cấp máy chủ'}).status_code==200
    assert TestClient(app).get('/api/config').json()['maintenance']['enabled'] is True
    r=rent(a); assert r.status_code==503 and 'Nâng cấp' in r.json()['detail']
    assert rent(ad).status_code==201
    ad.put('/api/admin/settings/maintenance',json={'enabled':False})
    assert rent(a).status_code==201

def test_restart_batch_schedule_and_sessions():
    a=client();t1=rent(a).json();t2=rent(a).json()
    assert a.post('/api/tabs/'+t1['id']+'/restart').json()['boot']==1
    r=a.post('/api/tabs/batch',json={'ids':[t1['id'],t2['id']],'action':'group','group':'Acc chính'}).json()
    assert r['done']==2 and all(x['group']=='Acc chính' for x in a.get('/api/tabs').json())
    assert a.post('/api/tabs/batch',json={'ids':[t1['id'],t2['id']],'action':'stop'}).json()['done']==2
    assert a.patch('/api/tabs/'+t1['id']+'/schedule',json={'restart_at':'25:00'}).status_code==422
    assert a.patch('/api/tabs/'+t1['id']+'/schedule',json={'restart_at':'04:30'}).json()['restart_at']=='04:30'
    with tx() as s:
        t=s.get(Tab,t2['id']);t.desired='running';t.restart_at='00:00';t.last_restart=0
    _hb()
    assert [x for x in a.get('/api/tabs').json() if x['id']==t2['id']][0]['boot']==1
    sess=a.get('/api/me/sessions').json()
    assert any(x['current'] for x in sess)
    other=client()
    mine=[x for x in a.get('/api/me/sessions').json() if not x['current']]
    assert a.delete('/api/me/sessions/'+mine[0]['id']).status_code==200
    assert other.get('/api/me').status_code==401 or a.get('/api/me').status_code==200

def test_expiry_notification_once():
    a=client();t=rent(a).json()
    with tx() as s: s.get(Tab,t['id']).expires=now()+3600
    _hb();_hb()
    titles=[n['title'] for n in a.get('/api/notifications').json()['items']]
    assert titles.count('Tab "Tab test" sắp hết hạn')==1

def test_thumbnails_and_logs_only_on_demand():
    import backend.app as m
    m.hub.thumb_seen.clear();m.hub.log_seen.clear()
    a=client();t=rent(a).json()
    hb=_hb()
    assert hb['watch']=={} and hb['logs']==[]          # nobody looking: nothing captured
    a.get('/api/tabs/'+t['id']+'/frame')
    a.get('/api/tabs/'+t['id']+'/logs')
    hb=_hb()
    assert hb['watch']=={t['id']:2} and hb['logs']==[t['id']]

def test_client_ip_behind_proxy():
    from starlette.requests import Request as R
    import backend.app as m
    def req(peer,headers):
        return R({'type':'http','client':(peer,1),'headers':[(k.encode(),v.encode()) for k,v in headers.items()]})
    assert m.client_ip(req('127.0.0.1',{'cf-connecting-ip':'203.0.113.7'}))=='203.0.113.7'
    assert m.client_ip(req('127.0.0.1',{'x-forwarded-for':'198.51.100.2, 10.0.0.1'}))=='198.51.100.2'
    assert m.client_ip(req('8.8.8.8',{'cf-connecting-ip':'203.0.113.7'}))=='8.8.8.8'      # spoof from the internet ignored
    assert m.client_ip(req('127.0.0.1',{'x-forwarded-for':'not-an-ip'}))=='127.0.0.1'

def test_cors_for_separate_frontend():
    c=TestClient(app)
    origin='http://127.0.0.1:8000'
    pre=c.options('/api/auth/login',headers={'Origin':origin,'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'content-type'})
    assert pre.status_code==200 and pre.headers['access-control-allow-origin']==origin and pre.headers['access-control-allow-credentials']=='true'
    bad=c.options('/api/auth/login',headers={'Origin':'https://evil.example','Access-Control-Request-Method':'POST'})
    assert 'access-control-allow-origin' not in bad.headers

def test_stream_bearer_subprotocol_cross_site():
    a=client();tab=rent(a).json();tok=a.headers['Authorization'][7:]
    c=TestClient(app)
    with c.websocket_connect('/api/tabs/'+tab['id']+'/stream',subprotocols=['bearer',tok],headers={'origin':'https://thuetab.pages.dev'}) as ws:
        assert ws.accepted_subprotocol=='bearer'
        assert json.loads(ws.receive_text())['type']=='hello'
    from starlette.websockets import WebSocketDisconnect
    with pytest.raises(WebSocketDisconnect) as e:
        with c.websocket_connect('/api/tabs/'+tab['id']+'/stream',subprotocols=['bearer','wrong'],headers={'origin':'https://thuetab.pages.dev'}) as ws: ws.receive_text()
    assert e.value.code==4401

def test_downloads_fall_back_to_github_release(monkeypatch):
    import backend.app as m
    monkeypatch.setattr(m,'release_assets',lambda: [
        {'name':'ThueTab-Android.apk','size':5,'updated':1,'url':'https://github.com/x/y/releases/download/v1/ThueTab-Android.apk'},
        {'name':'ThueTab-macOS.zip','size':6,'updated':1,'url':'https://github.com/x/y/releases/download/v1/ThueTab-macOS.zip'}])
    d=m.DATA_DIR/'downloads';d.mkdir(exist_ok=True)
    for f in d.iterdir(): f.unlink()
    (d/'ThueTab-Android.apk').write_bytes(b'PK')
    dl={x['platform']:x for x in TestClient(app).get('/api/config').json()['downloads']}
    assert dl['android']['url']=='/api/downloads/ThueTab-Android.apk'      # local build wins
    assert dl['macos']['url'].startswith('https://github.com/')              # missing locally -> release link

def test_order_code_matches_sepay_default_template():
    import re as _re
    c=client();ad=client('admin@test.vn')
    o=c.post('/api/wallet/orders',json={'amount':20000}).json()
    assert _re.fullmatch(r'TT\d{10}',o['code'])
    webhook=TestClient(app);headers={'Authorization':'Apikey '+os.environ['SEPAY_API_KEY']}
    before=c.get('/api/me').json()['balance']
    b={'id':777001,'accountNumber':'123456789','gateway':'Vietcombank','referenceCode':'FT777','transferType':'in',
       'transferAmount':20000,'content':'MBVCB.123 '+o['code']+' chuyen tien','code':o['code']}
    assert webhook.post('/api/payments/sepay',headers=headers,json=b).json()['matched'] is True
    assert c.get('/api/me').json()['balance']==before+20000


def test_download_archives_matched_by_name(tmp_path, monkeypatch):
    # Windows and macOS builds are both .zip: the platform comes from the file name.
    import backend.app as m
    d=m.DATA_DIR/'downloads'; d.mkdir(parents=True,exist_ok=True)
    for f in d.glob('*'): f.unlink()
    for n in ('ThueTab-Windows.zip','ThueTab-macOS.zip','ThueTab-Linux.tar.gz'): (d/n).write_bytes(b'PK')
    try:
        dl={x['platform']:x['file'] for x in TestClient(app).get('/api/config').json()['downloads']}
        assert dl=={'windows':'ThueTab-Windows.zip','macos':'ThueTab-macOS.zip','linux':'ThueTab-Linux.tar.gz'}
    finally:
        for f in d.glob('*'): f.unlink()


def test_config_exposes_web_url_for_app_links():
    # Share/referral links from the native app must point at the web front-end, not the API host.
    import backend.app as m
    assert TestClient(app).get('/api/config').json()['web_url']==m.ORIGINS[0]


def test_api_host_forwards_browser_links_to_web():
    # Without a bundled web build, opening https://<api>/#/s/TOKEN must land on the web front-end.
    import backend.app as m
    if m.DIST.exists(): return
    r=TestClient(app).get('/')
    assert r.status_code==200 and 'location.replace' in r.text and m.ORIGINS[0] in r.text
    assert TestClient(app).get('/api/nope').status_code==404
