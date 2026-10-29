"""Operator-only setup commands. No public endpoint can grant credit or administrator rights."""
import sys, os, getpass, argparse
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from backend.app import ph, uid, tx, audit
from backend.db import Base,engine,User,Ledger,Worker,Tab,Slot,CustomJar,Order,AuthSession
from backend.app import purge_user
from sqlalchemy import delete
from sqlalchemy import select
parser=argparse.ArgumentParser()
sub=parser.add_subparsers(dest='cmd',required=True)
p=sub.add_parser('create-admin');p.add_argument('--email',required=True);p.add_argument('--name',default='Quản trị viên')
p=sub.add_parser('credit');p.add_argument('--email',required=True);p.add_argument('--amount',type=int,required=True);p.add_argument('--reason',required=True)
p=sub.add_parser('approve-trial');p.add_argument('--email',required=True)
p=sub.add_parser('delete-user');p.add_argument('--email',required=True)
p=sub.add_parser('add-worker');p.add_argument('--id',required=True);p.add_argument('--capacity',type=int,default=4)
a=parser.parse_args();Base.metadata.create_all(engine)
leftovers=[]  # files removed only after the database change commits
with tx() as s:
    if a.cmd=='add-worker':
        if not 1<=a.capacity<=100: raise SystemExit('Invalid capacity')
        if s.get(Worker,a.id): raise SystemExit('Worker exists')
        s.add(Worker(id=a.id,capacity=a.capacity));print('Worker provisioned')
    else:
        email=a.email.strip().lower()
        u=s.scalar(select(User).where(User.email==email).with_for_update())
        if a.cmd=='create-admin':
            if u: raise SystemExit('Account exists. Refusing to overwrite.')
            password=os.getenv('INITIAL_ADMIN_PASSWORD','')
            if password and len(password)<10: raise SystemExit('Password too short')
            # Interactive: ask again instead of aborting a half-finished install.
            while len(password)<10:
                password=getpass.getpass('Mật khẩu admin (ít nhất 10 ký tự): ')
                if len(password)<10: print('Mật khẩu quá ngắn, nhập lại.'); continue
                if getpass.getpass('Nhập lại mật khẩu: ')!=password: print('Hai lần nhập không khớp.'); password=''
            s.add(User(id=uid(),email=email,name=a.name,password=ph.hash(password),role='admin',trial_approved=1));print('Administrator created')
        elif not u: raise SystemExit('Account not found')
        elif a.cmd=='delete-user':
            if u.role=='admin': raise SystemExit('Refusing to delete an administrator')
            leftovers=purge_user(s,u);audit(s,'operator','user.delete',email);print('Deleted')
        elif a.cmd=='credit':
            if a.amount<=0: raise SystemExit('Positive credit only')
            u.balance+=a.amount;s.add(Ledger(id=uid(),user_id=u.id,amount=a.amount,description=a.reason[:160]));audit(s,'operator','wallet.manual-credit',u.id);print('Done')
        else: u.trial_approved=1;audit(s,'operator','trial.approve',u.id);print('Done')
for f in leftovers: f.unlink(missing_ok=True)
