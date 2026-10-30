"""Trusted local worker. Only this process can access Docker; never expose its socket to API."""
import os, time, json, shlex, shutil, logging, threading
from pathlib import Path
import docker, httpx
from docker.errors import NotFound
ROOT=Path(__file__).resolve().parents[1]
CATALOG={g['id']:g for g in json.loads((ROOT/'backend/catalog.json').read_text()) if g['enabled']}
TOKEN=os.environ['WORKER_TOKEN']
if len(TOKEN)<32: raise SystemExit('WORKER_TOKEN must be at least 32 characters')
API=os.getenv('API_URL','http://127.0.0.1:8000')
WS_API='ws'+API.removeprefix('http')
WORKER=os.getenv('WORKER_ID','local-1')
# CPU cap per tab (a ceiling, not a reservation: idle tabs leave their share to busy ones). The emulator and the
# video encoder share it, so below ~1 CPU both stutter while someone is watching.
TAB_NANO_CPUS=int(float(os.getenv('TAB_CPUS','1'))*1e9)
# Live video bitrate cap (kbit/s) per watched tab. ~600 fits a home uplink of ~1 Mbit/s with headroom.
STREAM_KBPS=max(150,int(os.getenv('STREAM_KBPS','600')))
client=docker.from_env(timeout=8)
http=httpx.Client(base_url=API,headers={'Authorization':'Bearer '+TOKEN},timeout=8)
logging.basicConfig(level=logging.INFO,format='%(asctime)s %(levelname)s %(message)s')
logging.getLogger('httpx').setLevel(logging.WARNING)
LABELS={'thuetab.managed':'true','thuetab.worker':WORKER}
def containers(): return {c.labels['thuetab.tab']:c for c in client.containers.list(all=True,filters={'label':[f'{k}={v}' for k,v in LABELS.items()]})}
def remove(c):
    try: c.remove(force=True)
    except NotFound: pass

def ensure_network(net_name="thuetab-game-net"):
    try:
        return client.networks.get(net_name)
    except NotFound:
        try:
            net = client.networks.create(
                net_name,
                driver="bridge",
                options={
                    "com.docker.network.bridge.enable_icc": "false",
                    "com.docker.network.bridge.name": "br-thuetab"
                },
                labels={"thuetab.managed": "true"}
            )
            logging.info("Created isolated bridge network: %s", net_name)
            return net
        except Exception as e:
            logging.warning("Cannot create network %s: %s", net_name, e)
            return None

# The emulated J2ME screen is drawn just below the emulator's 21px menu bar, at x=0.
SCREEN_ORIGIN=(0,21)
def screen(t):
    if t.get('kind')!='midp': return '640x480'
    return t.get('screen') if t.get('screen') in ('240x320','320x240','360x640','640x360','176x220') else '240x320'

IMAGE_IDS={}
def image_id(name):
    # Resolved once per worker start: after rebuilding the game image, restarting the worker rolls every tab onto it.
    if name not in IMAGE_IDS:
        try: IMAGE_IDS[name]=client.images.get(name).id[7:19]
        except Exception: IMAGE_IDS[name]=''
    return IMAGE_IDS[name]

def revision(t):
    # Changes whenever the tab switches game, JAR, screen, restarts, or the game image is updated.
    g=CATALOG.get(t['game'],{})
    return f"{t['game']}:{t.get('custom_jar_id') or ''}:{screen(t)}:{t.get('boot',0)}:{image_id(g.get('image',''))}"

def start(t):
    g=CATALOG.get(t['game'])
    if not g or not g['image']: raise ValueError('Game not installed')
    network=g.get('network','thuetab-game-net')
    allow_egress = os.getenv('ALLOW_FILTERED_EGRESS', 'true').lower() == 'true'
    if network not in ('none', 'host') and not allow_egress:
        raise ValueError('Filtered egress has not been approved')
    
    extra_kwargs = {}
    if network != 'none':
        ensure_network(network)
        extra_kwargs['network'] = network
        extra_kwargs['dns'] = ['8.8.8.8', '1.1.1.1']
    else:
        extra_kwargs['network_mode'] = 'none'

    if t.get('custom_jar_id'):
        jar_file = (Path(os.getenv('DATA_DIR', ROOT/'data')) / 'jars' / f"{t['custom_jar_id']}.jar").resolve()
        # Never fall back to the bundled demo when the user's JAR is gone.
        if not jar_file.is_file(): raise ValueError('Custom JAR missing')
        extra_kwargs['volumes'] = {str(jar_file): {'bind': '/opt/game/game.jar', 'mode': 'ro'}}

    return client.containers.run(
        g['image'],
        detach=True,
        name='thuetab-'+t['id'],
        labels={**LABELS,'thuetab.tab':t['id'],'thuetab.rev':revision(t)},
        hostname='tab',
        user='10001:10001',
        read_only=True,
        cap_drop=['ALL'],
        security_opt=['no-new-privileges:true'],
        mem_limit='512m',
        memswap_limit='512m',
        nano_cpus=TAB_NANO_CPUS,
        pids_limit=96,
        shm_size='32m',
        tmpfs={'/tmp':'rw,nosuid,nodev,size=64m,mode=1777'},
        environment={'DISPLAY':':99','HOME':'/tmp/home','GAME_KIND':t.get('kind','jar'),'MIDLET_CLASS':t.get('midlet',''),
                     'SCREEN_W':screen(t).split('x')[0],'SCREEN_H':screen(t).split('x')[1]},
        log_config=docker.types.LogConfig(type='json-file',config={'max-size':'1m','max-file':'2'}),
        **extra_kwargs
    )

KEYS={'Up','Down','Left','Right','Return','Escape','space','BackSpace','F1','F2','asterisk','numbersign','0','1','2','3','4','5','6','7','8','9'}
def xdotool_args(t,cmd):
    if cmd.get('hold') in ('down','up') and cmd.get('key') in KEYS: return ['key'+cmd['hold'],cmd['key']]
    if cmd.get('key') in KEYS: return ['key','--clearmodifiers',cmd['key']]
    if cmd.get('key') in ('@tap','@swipe'):
        pts=[int(v) for v in cmd['text'].split(',')]
        # Frame pixels -> X display coordinates.
        ox,oy=SCREEN_ORIGIN if t.get('kind')=='midp' else (0,0)
        x,y=pts[0]+ox,pts[1]+oy
        if cmd['key']=='@tap': return ['mousemove',str(x),str(y),'click','1']
        return ['mousemove',str(x),str(y),'mousedown','1','mousemove','--sync',str(pts[2]+ox),str(pts[3]+oy),'mouseup','1']
    # Argument list, no shell: text is passed verbatim to xdotool.
    if cmd.get('text'): return ['type','--delay','40','--',cmd['text'][:64]]
    return None

def send_input(c,t,cmd):
    args=xdotool_args(t,cmd)
    if args: c.exec_run(['xdotool',*args],environment={'DISPLAY':':99'})

class InputPipe:
    """One long-lived shell in the tab reading xdotool commands from stdin. A docker exec per key costs
    ~100-300 ms; a line on an open pipe reaches the game in a few ms."""
    def __init__(self,docker_api,name):
        # Each line is a shell-quoted argument list (shlex.quote), so eval only ever runs xdotool.
        exec_id=docker_api.api.exec_create(name,['sh','-c','while IFS= read -r l; do eval "xdotool $l"; done'],
                                           stdin=True,environment={'DISPLAY':':99'})['Id']
        self.sock=docker_api.api.exec_start(exec_id,socket=True)._sock

    def send(self,t,cmd):
        args=xdotool_args(t,cmd)
        if args: self.sock.sendall((' '.join(shlex.quote(a.replace('\n',' ')) for a in args)+'\n').encode())

    def close(self):
        try: self.sock.close()
        except Exception: pass

AUD=b'\x00\x00\x00\x01\x09'  # H.264 access unit delimiter NAL
THUMBS=set()  # tabs whose thumbnail someone is looking at (from the heartbeat)
THUMB_FPS=5
# Thumbnails (tab cards, multi-screen wall) are small tiles: at most 240 px wide, so 5 fps costs ~25–40 KB/s
# per tile instead of ~200 KB/s at full size. Exact colour conversion (see the H.264 note in Streamer.ffmpeg).
THUMB_VF='scale=w=min(240\\,iw):h=-2:flags=bilinear+accurate_rnd+full_chroma_int'

class Streamer:
    """Live MJPEG from ffmpeg x11grab inside the tab's container, relayed to the API over a WebSocket.
    Runs only while someone is watching; input arriving on the same socket is applied immediately."""
    def __init__(self,t,fps,codec='mjpeg'):
        self.t=t;self.fps=fps;self.codec=codec;self.stop=threading.Event();self.container=None
        self.pidfile=f'/tmp/stream-{os.urandom(4).hex()}.pid'
        threading.Thread(target=self.run,daemon=True,name='stream-'+t['id']).start()

    def ffmpeg(self):
        midp=self.t.get('kind')=='midp'
        size,origin=(screen(self.t),f':99.0+{SCREEN_ORIGIN[0]},{SCREEN_ORIGIN[1]}') if midp else ('640x480',':99.0')
        w,h=map(int,size.split('x'))
        # PID file lets stop() kill ffmpeg: closing the exec stream alone leaves it running. Constant frame rate
        # while someone watches (nobody watching = no capture); -flush_packets 1 sends each frame as soon as it's encoded.
        # Any encoder left over from an earlier stream of this tab is stopped first: two encoders feeding one tab
        # double the frame rate and interleave two unrelated videos (smeared, blocky picture).
        grab=('pkill -x ffmpeg 2>/dev/null; echo $$ > "$0"; exec ffmpeg -loglevel error -fflags nobuffer -f x11grab -draw_mouse 0 -framerate "$1" '
              '-video_size "$2" -i "$3" ')
        if self.codec=='h264':
            # H.264 sends only what changed between frames: ~10x less data than JPEG, so 30/60 fps fits a slow uplink.
            # The minimal FFmpeg has no assembly: its fast RGB->YUV path garbles chroma (green/magenta stripes), so
            # convert with the exact path. Baseline + zerolatency: no B-frames or lookahead (no added delay), decodable by every browser.
            # Two keyframes per second let a viewer that fell behind (or just joined) resynchronise within ~0.5 s; aud=1 marks frame
            # boundaries so the stream can be cut into frames below. "superfast" (not ultrafast) keeps motion
            # search and the deblocking filter: at the same bitrate the picture is far sharper, for a few % CPU
            # at these small game resolutions.
            kbps=STREAM_KBPS
            return ['sh','-c',grab+'-vf scale=flags=accurate_rnd+full_chroma_int,format=yuv420p '
                    '-c:v libx264 -preset superfast -tune zerolatency -profile:v baseline '
                    '-g "$6" -crf 21 -maxrate "$4"k -bufsize "$5"k -x264-params aud=1 -f h264 -flush_packets 1 -',
                    self.pidfile,str(self.fps),size,origin,str(kbps),str(kbps//2),str(max(self.fps//2,5))]
        if self.fps<=THUMB_FPS:
            # Nobody watches live, only thumbnails: small tiles.
            return ['sh','-c',grab+'-vf "$4" -f mjpeg -q:v 8 -flush_packets 1 -',self.pidfile,str(self.fps),size,origin,THUMB_VF]
        # JPEG (native app 1.1, old browsers): bigger screens get lighter compression so the tab keeps its frame rate.
        quality='4' if w*h<=240*320 else '7'
        return ['sh','-c',grab+'-f mjpeg -q:v "$4" -flush_packets 1 -',self.pidfile,str(self.fps),size,origin,quality]

    def kill_ffmpeg(self,container):
        try: container.exec_run(['sh','-c','[ -f "$0" ] && kill "$(cat "$0")"; rm -f "$0"',self.pidfile])
        except Exception: pass

    def close(self):
        self.stop.set()
        if self.container: threading.Thread(target=self.kill_ffmpeg,args=(self.container,),daemon=True).start()

    def run(self):
        from websockets.sync.client import connect
        docker_api=docker.from_env(timeout=8)
        name='thuetab-'+self.t['id']
        while not self.stop.is_set():
            try:
                with connect(WS_API+'/api/internal/stream/'+self.t['id'],additional_headers={'Authorization':'Bearer '+TOKEN},max_size=2**20,open_timeout=5) as ws:
                    container=self.container=docker_api.containers.get(name)
                    logging.info('Stream %s: %s fps %s',self.t['id'][:8],self.fps,self.codec)
                    threading.Thread(target=self.inputs,args=(ws,container,docker_api,name),daemon=True).start()
                    if self.codec=='h264':
                        threading.Thread(target=self.thumbs,args=(container,),daemon=True).start()
                    exec_id=docker_api.api.exec_create(name,self.ffmpeg(),environment={'DISPLAY':':99'})['Id']
                    buf=b''
                    for out,_ in docker_api.api.exec_start(exec_id,stream=True,demux=True):
                        if self.stop.is_set(): break
                        if not out: continue
                        buf+=out
                        if self.codec=='h264':
                            # Each frame starts with an access unit delimiter; a frame is complete when the next begins.
                            while True:
                                start=buf.find(AUD)
                                end=buf.find(AUD,start+5) if start>=0 else -1
                                if end<0: break
                                ws.send(buf[start:end]);buf=buf[end:]
                        else:
                            # Split the MJPEG byte stream on JPEG start/end markers.
                            while True:
                                start=buf.find(b'\xff\xd8')
                                end=buf.find(b'\xff\xd9',start+2) if start>=0 else -1
                                if end<0: break
                                ws.send(buf[start:end+2]);buf=buf[end+2:]
                        if len(buf)>2_000_000: buf=b''
            except Exception as e:
                if not self.stop.is_set(): logging.info('Stream %s restarting: %s',self.t['id'][:8],type(e).__name__)
            if self.container: self.kill_ffmpeg(self.container)
            self.stop.wait(2)
        docker_api.close()

    def thumbs(self,container):
        """While the live view is video, thumbnails (tab cards, wall) get their own small 5 fps JPEG feed, only while
        someone is looking at them. Those frames go to /internal/frames and never enter the video stream."""
        midp=self.t.get('kind')=='midp'
        size,origin=(screen(self.t),f':99.0+{SCREEN_ORIGIN[0]},{SCREEN_ORIGIN[1]}') if midp else ('640x480',':99.0')
        pidfile=f'/tmp/thumb-{os.urandom(4).hex()}.pid'
        api=docker.from_env(timeout=8)
        try:
            while not self.stop.wait(0.5):
                if self.t['id'] not in THUMBS: continue
                # Bounded run (timeout): if this thread dies, the encoder still ends by itself.
                cmd=['sh','-c','echo $$ > "$0"; exec timeout 30 ffmpeg -loglevel error -f x11grab -draw_mouse 0 -framerate "$1" '
                     '-video_size "$2" -i "$3" -vf "$4" -f mjpeg -q:v 8 -flush_packets 1 -',pidfile,str(THUMB_FPS),size,origin,THUMB_VF]
                try:
                    exec_id=api.api.exec_create(container.id,cmd,environment={'DISPLAY':':99'})['Id']
                    buf=b''
                    for out,_ in api.api.exec_start(exec_id,stream=True,demux=True):
                        if self.stop.is_set() or self.t['id'] not in THUMBS: break
                        if not out: continue
                        buf+=out
                        while True:
                            start=buf.find(b'\xff\xd8')
                            end=buf.find(b'\xff\xd9',start+2) if start>=0 else -1
                            if end<0: break
                            http.put('/api/internal/frames/'+self.t['id'],content=buf[start:end+2]);buf=buf[end+2:]
                        if len(buf)>2_000_000: buf=b''
                except Exception: pass
                try: container.exec_run(['sh','-c','[ -f "$0" ] && kill "$(cat "$0")"; rm -f "$0"',pidfile])
                except Exception: pass
        finally:
            api.close()

    def inputs(self,ws,container,docker_api,name):
        box=[None]  # the InputPipe, swapped when it breaks
        try: box[0]=InputPipe(docker_api,name)
        except Exception: pass
        lock=threading.Lock()
        held={}  # key -> [time of the last keydown from a viewer, pressed at, last repeat]
        def deliver(cmd):
            with lock:
                try:
                    if box[0]: box[0].send(self.t,cmd)
                    else: send_input(container,self.t,cmd)
                except Exception:
                    # Pipe broke (tab restarted): this key goes the slow way, the next ones through a new pipe.
                    if box[0]: box[0].close()
                    try: send_input(container,self.t,cmd);box[0]=InputPipe(docker_api,name)
                    except Exception: box[0]=None
        done=threading.Event()
        def repeat_and_release():
            # Like a real keypad: a held key presses again every HOLD_EVERY s after HOLD_AFTER s (games that move
            # on each press keep moving; games that read the key state see it down the whole time). The viewer
            # re-sends keydown every ~0.4 s while the finger stays down; if that stops (connection lost, app
            # closed) the key is let go here, so a game never keeps walking on its own.
            while not done.wait(0.05):
                t=time.monotonic()
                for k,h in list(held.items()):
                    if t-h[0]>HOLD_TIMEOUT:
                        if held.pop(k,None) is not None: deliver({'key':k,'hold':'up'})
                    elif t-h[1]>=HOLD_AFTER and t-h[2]>=HOLD_EVERY:
                        h[2]=t
                        deliver({'key':k,'hold':'down'})
        threading.Thread(target=repeat_and_release,daemon=True).start()
        try:
            for raw in ws:
                if isinstance(raw,str):
                    cmd=json.loads(raw)
                    k,hold=cmd.get('key'),cmd.get('hold')
                    if hold=='down':
                        if k in held:
                            held[k][0]=time.monotonic()  # still held: refresh only, repeats come from the thread
                            continue
                        now_=time.monotonic()
                        held[k]=[now_,now_,now_]
                    elif hold=='up':
                        if held.pop(k,None) is None: continue
                    deliver(cmd)
        except Exception: pass
        finally:
            done.set()
            for k in list(held): deliver({'key':k,'hold':'up'})
            if box[0]: box[0].close()

streamers={}
SETTLE_SECONDS=6
HOLD_TIMEOUT=1.5  # s without a keydown refresh before a held key is released
HOLD_AFTER,HOLD_EVERY=0.35,0.1  # held keys repeat like a phone keypad (same timing as the web keypad)
def sync_streams(watch,desired,video=()):
    codec=lambda id:'h264' if id in video else 'mjpeg'
    for id,s in list(streamers.items()):
        if id not in watch or id not in desired or s.fps!=watch[id] or s.codec!=codec(id) or revision(s.t)!=revision(desired[id]):
            s.close();del streamers[id]
    for id,fps in watch.items():
        if id in desired and id not in streamers: streamers[id]=Streamer(desired[id],fps,codec(id))

def main():
    last_ok=0; lease=15; statuses={}; retry_at={}; log_at={}; started_at={}; memory=0
    while True:
        tick=time.monotonic()
        try:
            existing=containers()
            memory=memory_state['mb']
            for id,c in existing.items(): statuses[id]='running' if c.status=='running' else 'error'
            r=http.post('/api/internal/heartbeat',json={'id':WORKER,'statuses':statuses,'memory_mb':memory,'system':dict(system_state)});r.raise_for_status()
            payload=r.json();last_ok=time.monotonic();heartbeat_state['last_ok']=last_ok;lease=min(15,payload['lease_seconds'])
            desired={t['id']:t for t in payload['tabs'] if t['desired']=='running' and t['expires']>time.time()}
            for id,c in existing.items():
                if id not in desired: remove(c);statuses[id]='stopped'
            for id,t in desired.items():
                c=existing.get(id)
                if c and c.labels.get('thuetab.rev')!=revision(t):
                    remove(c);c=None;retry_at.pop(id,None)
                if c and c.attrs['HostConfig'].get('NanoCpus')!=TAB_NANO_CPUS:
                    # TAB_CPUS changed: apply in place, the game keeps running.
                    try: client.api._result(client.api._post_json(client.api._url('/containers/{0}/update',c.id),data={'NanoCpus':TAB_NANO_CPUS}),True)
                    except Exception as e: logging.warning('Cannot update CPU of %s: %s',id,type(e).__name__)
                if c and c.status!='running':
                    remove(c);c=None
                    if id not in retry_at: retry_at[id]=tick+15
                if not c and tick>=retry_at.get(id,0):
                    try: c=start(t);statuses[id]='queued';retry_at[id]=tick+30;started_at[id]=tick
                    except Exception as e: statuses[id]='error';retry_at[id]=tick+30;logging.error('Cannot start %s: %s',id,type(e).__name__)
                # Logs only travel while someone has the log panel open.
                if c and c.status=='running' and id in payload.get('logs',()) and tick-log_at.get(id,0)>5:
                        log_at[id]=tick
                        http.put('/api/internal/logs/'+id,content=c.logs(tail=80,stdout=True,stderr=True)[-16000:],headers={'Content-Type':'text/plain'})
            running={k:v for k,v in desired.items() if existing.get(k) and existing[k].status=='running' and existing[k].labels.get('thuetab.rev')==revision(v)
                     and tick-started_at.get(k,-99)>SETTLE_SECONDS}
            THUMBS.clear();THUMBS.update(payload.get('thumbs',[]))
            sync_streams(payload.get('watch',{}),running,set(payload.get('video',[])))
            for cmd in payload['commands']:
                if cmd['tab_id'] in desired: send_input(client.containers.get('thuetab-'+cmd['tab_id']),desired[cmd['tab_id']],cmd)
            # Expired frame files are cleaned by API maintenance, not trusted game containers.
        except KeyboardInterrupt:
            for c in containers().values(): remove(c)
            break
        except Exception as e:
            logging.warning('Worker cycle failed: %s',type(e).__name__)
        # Lease safety: a separate watchdog thread also stops containers if this loop blocks.
        heartbeat_state['last_ok']=last_ok
        time.sleep(max(.1,2-(time.monotonic()-tick)))

heartbeat_state={'last_ok':0}
memory_state={'mb':0}
system_state={}  # host + per-tab resource figures sent with every heartbeat (admin "Hệ thống" view)

def _cpu_times():
    f=[int(x) for x in Path('/proc/stat').read_text().split('\n',1)[0].split()[1:]]
    idle=f[3]+(f[4] if len(f)>4 else 0)
    return sum(f),idle

def _net_bytes():
    # Physical/virtual NICs only: loopback, Docker bridges and container veths would count traffic twice.
    rx=tx=0
    for line in Path('/proc/net/dev').read_text().splitlines()[2:]:
        name,data=line.split(':',1)
        name=name.strip()
        if name=='lo' or name.startswith(('veth','docker','br-','virbr','cni','flannel')): continue
        v=data.split();rx+=int(v[0]);tx+=int(v[8])
    return rx,tx

def _meminfo():
    m={}
    for line in Path('/proc/meminfo').read_text().splitlines():
        k,v=line.split(':',1);m[k]=int(v.split()[0])//1024
    return m

def _disk(path):
    try:
        d=shutil.disk_usage(path)
        return {'total_mb':d.total//1048576,'used_mb':(d.total-d.free)//1048576}
    except OSError: return None

def system_sampler():
    """Host figures every 5 s (cheap /proc reads); per-tab CPU/RAM from docker stats every 30 s (~1 s per tab)."""
    api=docker.from_env(timeout=10)
    prev_cpu=_cpu_times();prev_net=_net_bytes();prev_at=time.monotonic();tabs_at=0;tabs=[]
    while True:
        time.sleep(5)
        try:
            cpu=_cpu_times();net=_net_bytes();at=time.monotonic();dt=max(at-prev_at,0.001)
            busy=(cpu[0]-prev_cpu[0])-(cpu[1]-prev_cpu[1]);total=max(cpu[0]-prev_cpu[0],1)
            m=_meminfo()
            if at-tabs_at>=30:
                tabs_at=at;tabs=[];mem_total=0
                for c in api.containers.list(filters={'label':[f'{k}={v}' for k,v in LABELS.items()]}):
                    try:
                        st=c.stats(stream=False)
                        cd=st['cpu_stats']['cpu_usage']['total_usage']-st['precpu_stats']['cpu_usage']['total_usage']
                        sd=st['cpu_stats'].get('system_cpu_usage',0)-st['precpu_stats'].get('system_cpu_usage',0)
                        n=st['cpu_stats'].get('online_cpus') or os.cpu_count() or 1
                        mem=st['memory_stats'].get('usage',0)//1048576;mem_total+=mem
                        tabs.append({'tab_id':c.labels.get('thuetab.tab',''),'cpu':round(cd/sd*n*100,1) if sd>0 else 0.0,'mem_mb':mem})
                    except Exception: pass
                memory_state['mb']=mem_total
            system_state.update({
                'cpu':round(busy*100/total,1),'cores':os.cpu_count() or 1,'load':[round(x,2) for x in os.getloadavg()],
                'mem_total_mb':m.get('MemTotal',0),'mem_used_mb':m.get('MemTotal',0)-m.get('MemAvailable',0),
                'swap_total_mb':m.get('SwapTotal',0),'swap_used_mb':m.get('SwapTotal',0)-m.get('SwapFree',0),
                'disk':_disk(str(ROOT/'data')),'docker_disk':_disk('/var/lib/docker') if Path('/var/lib/docker').exists() else None,
                'net_rx_bps':int((net[0]-prev_net[0])/dt),'net_tx_bps':int((net[1]-prev_net[1])/dt),
                'uptime':int(float(Path('/proc/uptime').read_text().split()[0])),'tabs':tabs[:100],'at':int(time.time())})
            prev_cpu,prev_net,prev_at=cpu,net,at
        except Exception as e:
            logging.warning('System sampler: %s',type(e).__name__)
def watchdog():
    # Independent Docker connection; HTTP or screenshot work must not bypass lease expiration.
    guard=docker.from_env(timeout=5)
    while True:
        time.sleep(2)
        if time.monotonic()-heartbeat_state['last_ok']>20:
            for c in guard.containers.list(all=True,filters={'label':[f'{k}={v}' for k,v in LABELS.items()]}):
                try: c.remove(force=True)
                except Exception: pass
if __name__=='__main__':
    import threading
    threading.Thread(target=watchdog,daemon=True).start()
    threading.Thread(target=system_sampler,daemon=True).start()
    main()
