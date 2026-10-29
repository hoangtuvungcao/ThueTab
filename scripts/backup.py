"""Consistent local SQLite backup; PostgreSQL: use pg_dump as documented."""
import sqlite3,datetime,os
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=root/'data/thuetab.db'
if not source.exists(): raise SystemExit('Local database not found')
backup_dir=root/'data/backups';backup_dir.mkdir(exist_ok=True)
path=backup_dir/('thuetab-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')+'.db')
with sqlite3.connect(source) as src,sqlite3.connect(path) as dest: src.backup(dest)
path.chmod(0o600)
print(path)
