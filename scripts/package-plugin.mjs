import { copyFile, cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import './build-plugin-client.mjs';
const root = resolve(import.meta.dirname, '..');
const output = resolve(root, '.artifacts/plugin-package');
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
const source = JSON.parse(await readFile(resolve(root, 'plugins/dsh-harmony/package.json')));
const gateway = JSON.parse(await readFile(resolve(root, 'gateway/package.json')));
await writeFile(resolve(output, 'package.json'), JSON.stringify({ ...source, dependencies: gateway.dependencies,
  bundledDependencies: Object.keys(gateway.dependencies),
  files: ['index.mjs', 'client.mjs', 'client.browser.js', 'gateway/src', 'gateway/public', 'notify/index.mjs',
    'cordis.patch.yml', 'icon.svg', 'locale/*.json', 'README.md'] }, null, 2) + '\n');
await cp(resolve(root, 'gateway/src'), resolve(output, 'gateway/src'), { recursive: true });
await cp(resolve(root, 'gateway/public'), resolve(output, 'gateway/public'), { recursive: true });
await cp(resolve(root, 'plugins/pocket-notify'), resolve(output, 'notify'), { recursive: true });
await cp(resolve(root, 'plugins/dsh-harmony/client.mjs'), resolve(output, 'client.mjs'));
await cp(resolve(root, 'plugins/dsh-harmony/client.browser.js'), resolve(output, 'client.browser.js'));
await cp(resolve(root, 'plugins/dsh-harmony/cordis.patch.yml'), resolve(output, 'cordis.patch.yml'));
await cp(resolve(root, 'plugins/dsh-harmony/icon.svg'), resolve(output, 'icon.svg'));
await cp(resolve(root, 'plugins/dsh-harmony/locale'), resolve(output, 'locale'), { recursive: true });
let entry = await readFile(resolve(root, 'plugins/dsh-harmony/index.mjs'), 'utf8');
entry = entry.replaceAll("'../../gateway/", "'./gateway/").replaceAll("'../pocket-notify/", "'./notify/");
await writeFile(resolve(output, 'index.mjs'), entry);
await cp(resolve(root, 'plugins/dsh-harmony/README.md'), resolve(output, 'README.md'));
const npmArgs = ['install', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'];
const install = spawnSync(process.platform === 'win32' ? process.execPath : 'npm',
  process.platform === 'win32' ? [npmCliPath(), ...npmArgs] : npmArgs, { cwd: output, stdio: 'inherit' });
if (install.status !== 0) process.exit(install.status || 1);
const args = ['pack', '--ignore-scripts', '--pack-destination', resolve(root, '.artifacts')];
const result = spawnSync(process.platform === 'win32' ? process.execPath : 'npm',
  process.platform === 'win32' ? [npmCliPath(), ...args] : args, { cwd: output, stdio: 'inherit' });
if (result.status !== 0) process.exit(result.status || 1);
const artifact = resolve(root, `.artifacts/dsh-harmony-plugin-${source.version}.tgz`);
const verify = spawnSync(process.execPath, [resolve(root, 'scripts/verify-plugin-package.mjs'), artifact], {
  cwd: root, stdio: 'inherit'
});
if (verify.status !== 0) process.exit(verify.status || 1);
await copyFile(artifact, resolve(root, '.artifacts/dsh-harmony-plugin.tgz'));

function npmCliPath() {
  const path = [resolve(process.execPath, '..'), ...(process.env.PATH || '').split(';')]
    .map(dir => resolve(dir, 'node_modules/npm/bin/npm-cli.js')).find(candidate => existsSync(candidate));
  if (!path) throw Error('npm CLI was not found next to Node.js or on PATH');
  return path;
}
