"""Cross-platform local launcher: python scripts/local.py [--setup]"""
import os,sys,json,secrets,subprocess,signal,time,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
parser=argparse.ArgumentParser();parser.add_argument('--setup',action='store_true');parser.add_argument('--no-worker',action='store_true');a=parser.parse_args()
DATA=ROOT/'data';DATA.mkdir(exist_ok=True)
env=os.environ.copy();envfile=DATA/'local-env.json'
if not envfile.exists():
    envfile.write_text(json.dumps({'WORKER_TOKEN':secrets.token_urlsafe(48)}));envfile.chmod(0o600)
env.update(json.loads(envfile.read_text()))
env.setdefault('ALLOW_FILTERED_EGRESS', 'true')
python=ROOT/'.venv'/('Scripts/python.exe' if os.name=='nt' else 'bin/python')
npm='npm.cmd' if os.name=='nt' else 'npm'
if a.setup:
    if not python.exists(): subprocess.run([sys.executable,'-m','venv','.venv'],check=True)
    subprocess.run([str(python),'-m','pip','install','-r','backend/requirements.txt'],check=True)
    subprocess.run([npm,'ci'],cwd=ROOT/'web',check=True)
    subprocess.run([npm,'run','build'],cwd=ROOT/'web',check=True)
    subprocess.run(['docker','build','-f','runner/Dockerfile.game','-t','thuetab-java:local','.'],check=True)
    # Local-only credentials generated once, never fixed passwords shipped in source.
    from importlib.util import find_spec
    code='from backend.db import Base,engine;Base.metadata.create_all(engine)'
    subprocess.run([str(python),'-c',code],env=env,check=True)
    cred=DATA/'LOCAL_LOGIN.txt'
    if not cred.exists():
        password=secrets.token_urlsafe(15);setup_env={**env,'INITIAL_ADMIN_PASSWORD':password}
        subprocess.run([str(python),'scripts/manage.py','create-admin','--email','admin@thuetab.local','--name','Quản trị viên'],env=setup_env,check=True)
        cred.write_text('LOCAL TEST ONLY\nEmail: admin@thuetab.local\nPassword: '+password+'\n');cred.chmod(0o600)
if not python.exists(): raise SystemExit('Run: python scripts/local.py --setup')
children=[]
try:
    children.append(subprocess.Popen([str(python),'-m','uvicorn','backend.app:app','--host','127.0.0.1','--port','8000','--no-server-header'],env=env))
    time.sleep(2)
    if children[0].poll() is not None: raise SystemExit('API failed to start. Check port 8000.')
    if not a.no_worker: children.append(subprocess.Popen([str(python),'-m','runner.worker'],env=env))
    print('\nThuêTab: http://127.0.0.1:8000\nLocal login: data/LOCAL_LOGIN.txt\nCtrl+C to stop.',flush=True)
    while all(p.poll() is None for p in children): time.sleep(1)
finally:
    for p in reversed(children):
        if p.poll() is None: p.terminate()
    for p in children:
        try:p.wait(timeout=10)
        except subprocess.TimeoutExpired:p.kill()
    # Only remove this launcher's managed local-worker game containers.
    subprocess.run([str(python),'-c',"import docker;c=docker.from_env();[x.remove(force=True) for x in c.containers.list(all=True,filters={'label':['thuetab.managed=true','thuetab.worker=local-1']})]"],env=env)
