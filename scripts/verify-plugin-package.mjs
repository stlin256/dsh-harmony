import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import { createServer, request } from 'node:http';
import { spawnSync } from 'node:child_process';
const input = resolve(process.argv[2] || '');
if (!existsSync(input)) throw Error('Plugin package does not exist: ' + input);
const temporary = input.toLowerCase().endsWith('.tgz') ? await mkdtemp(resolve(tmpdir(), 'dsh-harmony-pack-')) : '';
if (temporary) {
  const extracted = spawnSync('tar', ['-xzf', input, '-C', temporary], { stdio: 'inherit' });
  if (extracted.status !== 0) { await rm(temporary, { recursive: true, force: true }); process.exit(extracted.status || 1); }
}
const packagePath = temporary ? resolve(temporary, 'package') : input;
const root = pathToFileURL(packagePath + '/');
try {
const pkg = JSON.parse(await readFile(new URL('package.json', root)));
const patchPath = pkg.dsh?.bundle?.patch;
if (typeof patchPath !== 'string') throw Error('Packed plugin does not declare dsh.bundle.patch');
const patch = await readFile(new URL(patchPath.replace(/^\.\//, ''), root), 'utf8');
if (!patch.includes("name: '@dsh-harmony/plugin'")) throw Error('Packed bundle patch does not register @dsh-harmony/plugin');
for (const locale of ['locale/en.json', 'locale/zh.json']) {
  const value = JSON.parse(await readFile(new URL(locale, root), 'utf8'));
  if (value.meta?.title !== 'DSH Harmony') throw Error('Packed locale metadata failed: ' + locale);
}
const plugin = await import(new URL('index.mjs', root));
const browser = await readFile(new URL(pkg.exports['./client'], root), 'utf8');
let registration;
runInNewContext(browser, { window: { __ModuleLoader__: { load: value => { registration = value; } } }, URL });
if (plugin.name !== 'dsh-harmony' || registration?.id !== '@dsh-harmony/plugin') throw Error('Packed plugin import failed');
const { createApp } = await import(new URL('gateway/src/app.mjs', root));
const { openStore } = await import(new URL('gateway/src/store.mjs', root));
const db = openStore(':memory:');
const pocket = createApp({ db, origin: 'https://dsh.example.com', upstream: 'http://127.0.0.1:3000',
  bootstrapSecret: 'package-check-bootstrap-'.repeat(3), eventSecret: 'package-check-events-'.repeat(3) });
const server = createServer(pocket.app);
await new Promise(done => server.listen(0, '127.0.0.1', done));
try {
  for (const path of ['/pocket/vendor.js', '/pocket/']) await new Promise((done, reject) => {
    const req = request({ hostname: '127.0.0.1', port: server.address().port, path, headers: { Host: 'dsh.example.com' } }, res => {
      res.resume(); res.once('end', () => res.statusCode === 200 ? done() : reject(Error('Packed asset rejected: ' + path + ' HTTP ' + res.statusCode)));
    });
    req.on('error', reject); req.end();
  });
  console.log('Packed plugin host, browser factory and static assets passed');
} finally { pocket.close(); server.closeAllConnections(); server.close(); db.close(); }
} finally {
  if (temporary) await rm(temporary, { recursive: true, force: true });
}
