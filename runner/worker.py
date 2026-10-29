"""Trusted local worker. Only this process can access Docker; never expose its socket to API."""
import os, time, json, shlex, logging, threading
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
        grab=('echo $$ > "$0"; exec ffmpeg -loglevel error -fflags nobuffer -f x11grab -draw_mouse 0 -framerate "$1" '
              '-video_size "$2" -i "$3" ')
        if self.codec=='h264':
            # H.264 sends only what changed between frames: ~10x less data than JPEG, so 30/60 fps fits a slow uplink.
            # The minimal FFmpeg has no assembly: its fast RGB->YUV path garbles chroma (green/magenta stripes), so
            # convert with the exact path. Baseline + zerolatency: no B-frames or lookahead (no added delay), decodable by every browser.
            # One keyframe per second lets a viewer that fell behind resynchronise quickly; aud=1 marks frame
            # boundaries so the stream can be cut into frames below.
            kbps=STREAM_KBPS
            return ['sh','-c',grab+'-vf scale=flags=accurate_rnd+full_chroma_int,format=yuv420p '
                    '-c:v libx264 -preset ultrafast -tune zerolatency -profile:v baseline '
                    '-g "$1" -crf 26 -maxrate "$4"k -bufsize "$5"k -x264-params aud=1 -f h264 -flush_packets 1 -',
                    self.pidfile,str(self.fps),size,origin,str(kbps),str(kbps//2)]
        # JPEG (thumbnails, native app): bigger screens get lighter compression so the tab keeps its frame rate.
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

    def inputs(self,ws,container,docker_api,name):
        try: pipe=InputPipe(docker_api,name)
        except Exception: pipe=None
        try:
            for raw in ws:
                if isinstance(raw,str):
                    cmd=json.loads(raw)
                    try:
                        if pipe: pipe.send(self.t,cmd)
                        else: send_input(container,self.t,cmd)
                    except Exception:
                        # Pipe broke (tab restarted): this key goes the slow way, the next ones through a new pipe.
                        if pipe: pipe.close()
                        try: send_input(container,self.t,cmd);pipe=InputPipe(docker_api,name)
                        except Exception: pipe=None
        except Exception: pass
        finally:
            if pipe: pipe.close()

streamers={}
SETTLE_SECONDS=6
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
            r=http.post('/api/internal/heartbeat',json={'id':WORKER,'statuses':statuses,'memory_mb':memory});r.raise_for_status()
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
def memory_sampler():
    # docker stats takes ~1 s per container; sample in the background so input and frames never wait on it.
    api=docker.from_env(timeout=10)
    while True:
        total=0
        try:
            for c in api.containers.list(filters={'label':[f'{k}={v}' for k,v in LABELS.items()]}):
                try: total+=c.stats(stream=False)['memory_stats'].get('usage',0)//1048576
                except Exception: pass
            memory_state['mb']=total
        except Exception: pass
        time.sleep(60)
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
    threading.Thread(target=memory_sampler,daemon=True).start()
    main()
