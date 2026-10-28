#!/usr/bin/env python3
"""Prepare the optional Pocket ID OIDC gateway; never overwrites an existing gateway."""
import argparse
from pathlib import Path
import os
import pwd
import grp
import shutil
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--harness-user', required=True)
a = p.parse_args()
if os.geteuid() != 0:
    raise SystemExit('Run as root')
source = Path(__file__).resolve().parent / 'pocket-id-gateway'
destination = Path('/opt/harness-passkey-gateway')
if destination.exists():
    raise SystemExit('Gateway exists. Use install-pocket-id.py to add the Harmony adapter.')
try:
    pwd.getpwnam('harness-gateway')
except KeyError:
    subprocess.run(['useradd', '--system', '--home-dir', '/var/lib/harness-gateway', '--shell', '/usr/sbin/nologin', 'harness-gateway'], check=True)
shutil.copytree(source, destination)
subprocess.run(['npm', 'ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=destination, check=True)
settings = Path('/etc/harness-gateway')
settings.mkdir(mode=0o700, exist_ok=True)
config = settings / 'gateway.env'
if not config.exists():
    text = (source / 'gateway.env.example').read_text().replace('/run/harness-gateway/launch-url', '/var/lib/dsh-harmony-launch/launch-url')
    config.write_text(text); config.chmod(0o600)
account = pwd.getpwnam(a.harness_user)
launch = Path('/var/lib/dsh-harmony-launch')
launch.mkdir(exist_ok=True)
os.chown(launch, account.pw_uid, grp.getgrnam('harness-gateway').gr_gid); launch.chmod(0o2750)
export = Path('/etc/systemd/system/deepseek-harness.service.d/dsh-harmony-launch.conf')
export.parent.mkdir(parents=True, exist_ok=True)
if not export.exists():
    export.write_text('[Service]\nEnvironment=DSH_HARMONY_LAUNCH_FILE=/var/lib/dsh-harmony-launch/launch-url\n')
node = shutil.which('node')
unit = Path('/etc/systemd/system/harness-gateway.service')
unit.write_text(f'''[Unit]
Description=DSH Harmony Pocket ID gateway
After=network-online.target deepseek-harness.service
Wants=network-online.target

[Service]
Type=simple
User=harness-gateway
Group=harness-gateway
WorkingDirectory={destination}
EnvironmentFile={config}
ExecStart={node} {destination}/src/server.mjs
Restart=on-failure
RestartSec=3
StateDirectory=harness-gateway
StateDirectoryMode=0700
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/harness-gateway

[Install]
WantedBy=multi-user.target
''')
print('Prepared. Configure the private gateway.env, Pocket ID client and HTTPS, then run install-pocket-id.py. No services started.')
