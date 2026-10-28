#!/usr/bin/env python3
"""Prepare the single Harness plugin and optional existing Pocket ID gateway adapter."""
import argparse
import grp
import os
from pathlib import Path
import pwd
import secrets
import shlex
import shutil
import subprocess
import json
from datetime import datetime, timezone

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--release', required=True, type=Path)
p.add_argument('--profile', required=True, type=Path)
p.add_argument('--harness-user', required=True)
p.add_argument('--harness-unit', default='deepseek-harness')
p.add_argument('--oidc-root', required=True, type=Path)
p.add_argument('--oidc-env', required=True, type=Path)
p.add_argument('--oidc-unit', default='harness-gateway')
a = p.parse_args()
if os.geteuid() != 0:
    raise SystemExit('Run as root')
release = a.release.resolve()
if not release.is_relative_to(Path('/srv/dsh-harmony/releases')) or not (release / 'plugins/dsh-harmony/index.mjs').is_file():
    raise SystemExit('Expected a complete release under /srv/dsh-harmony/releases')
for unit in (a.oidc_unit, a.harness_unit):
    if not unit.replace('-', '').isalnum():
        raise SystemExit('Invalid unit name')

def read_env(path):
    data = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        key, raw = line.split('=', 1)
        value = shlex.split(raw)
        data[key.strip()] = value[0] if value else ''
    return data

config = read_env(a.oidc_env)
source = a.oidc_root / 'src/server.mjs'
text = source.read_text()
if "./pocket-bridge.mjs" not in text:
    changes = [
      ("import http from 'node:http';", "import http from 'node:http';\nimport { PocketBridge as HarmonyPocketBridge } from './pocket-bridge.mjs';"),
      ('const proxy = new Proxy(config, store, harness);', '''const proxy = new Proxy(config, store, harness);
const pocketBridge = process.env.DSH_POCKET_UPSTREAM ? new HarmonyPocketBridge({
  target: process.env.DSH_POCKET_UPSTREAM, secret: process.env.DSH_POCKET_PROXY_SECRET,
  publicOrigin: config.publicUrl.origin, authOrigin: config.issuer.origin, idleAge: config.idleAge,
  uploadLimit: config.uploadLimit, validSession: id => store.byId(id),
  revokeSession: id => store.revoke(id), clearCookie: () => cookie(SESSION_COOKIE, '', 0),
}) : null;'''),
      ("  const current = session(request);\n  if (url.pathname === '/_gateway/logout'", "  const current = session(request);\n  if (pocketBridge && await pocketBridge.http(request, response, current, url)) return;\n  if (url.pathname === '/_gateway/logout'"),
      ('    requestURL(request, config);\n    const current = session(request);', '    const url = requestURL(request, config);\n    const current = session(request);\n    if (pocketBridge && await pocketBridge.upgrade(request, socket, head, current, url)) return;'),
      ('proxy.close(); server.close(', 'proxy.close(); pocketBridge?.close(); server.close('),
    ]
    for old, new in changes:
        if text.count(old) != 1:
            raise SystemExit('Unsupported gateway source; no files changed')
        text = text.replace(old, new, 1)

backup = Path('/var/backups/dsh-harmony') / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup.mkdir(parents=True, mode=0o700)
os.chmod(backup, 0o700)

def save(path):
    if path.exists():
        destination = backup / str(path).lstrip('/')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)

def write(path, value, mode=0o644, owner='root'):
    save(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.harmony-new')
    temp.write_text(value)
    account = pwd.getpwnam(owner)
    os.chown(temp, account.pw_uid, account.pw_gid)
    os.chmod(temp, mode)
    os.replace(temp, path)

for folder, dirs, files in os.walk(release):
    os.chmod(folder, 0o755)
    for name in files:
        item = Path(folder) / name
        if not item.is_symlink():
            os.chmod(item, item.stat().st_mode | 0o044)
envpath = Path('/etc/dsh-harmony/plugin.env')
previous = read_env(envpath) if envpath.exists() else {}
secret = previous.get('DSH_HARMONY_PROXY_SECRET') or secrets.token_urlsafe(48)
values = dict(DSH_HARMONY_PROXY_SECRET=secret, DSH_HARMONY_PUBLIC_ORIGIN=config['PUBLIC_URL'].rstrip('/'),
              DSH_HARMONY_AUTH_ORIGIN=config['OIDC_ISSUER'].rstrip('/'))
for key in ('HUAWEI_SERVICE_ACCOUNT', 'HUAWEI_CATEGORY', 'HUAWEI_TEST_MESSAGE'):
    if previous.get(key):
        values[key] = previous[key]
envpath.parent.mkdir(exist_ok=True, mode=0o700)
write(envpath, ''.join(f'{key}={shlex.quote(value)}\n' for key,value in values.items()), 0o600)
write(Path('/etc/systemd/system') / f'{a.harness_unit}.service.d/dsh-harmony.conf', f'[Service]\nEnvironmentFile={envpath}\n')
bridgeenv = a.oidc_env.parent / 'dsh-harmony.env'
target = config.get('HARNESS_UPSTREAM', 'http://127.0.0.1:3080')
write(bridgeenv, f'DSH_POCKET_UPSTREAM={target}\nDSH_POCKET_PROXY_SECRET={secret}\n', 0o600)
write(Path('/etc/systemd/system') / f'{a.oidc_unit}.service.d/dsh-harmony.conf', f'[Service]\nEnvironmentFile={bridgeenv}\n')
current = Path('/srv/dsh-harmony/current')
if current.is_symlink():
    (backup / 'previous-release.txt').write_text(str(current.resolve()) + '\n')
temp = current.with_name('current.harmony-new')
if temp.is_symlink():
    temp.unlink()
temp.symlink_to(release, target_is_directory=True)
os.replace(temp, current)
write(source, text)
write(a.oidc_root / 'src/pocket-bridge.mjs', (release / 'deploy/oidc-pocket-bridge.mjs').read_text())
for filename in ('package.json', 'pnpm-lock.yaml', 'cordis.patch.yml'):
    save(a.profile / filename)
home = pwd.getpwnam(a.harness_user).pw_dir
subprocess.run(['runuser', '-u', a.harness_user, '--', 'env', f'HOME={home}', 'pnpm', '--dir', str(a.profile), 'add',
                '--offline', '--ignore-scripts', '--config.auto-install-peers=false',
                '@dsh-harmony/plugin@link:/srv/dsh-harmony/current/plugins/dsh-harmony'], check=True)
patch = a.profile / 'cordis.patch.yml'
value = patch.read_text()
if '# DSH Harmony plugin' not in value:
    value += '\n# DSH Harmony plugin\n- insert:\n    - id: dsh-harmony\n      name: "@dsh-harmony/plugin"\n'
    write(patch, value, 0o600, a.harness_user)
subprocess.run(['/usr/local/bin/node', '--check', str(source)], check=True)
print(json.dumps({'prepared': True, 'backup': str(backup), 'release': str(release), 'restart': [a.harness_unit, a.oidc_unit]}))
