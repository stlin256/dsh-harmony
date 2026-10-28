import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import { createServer, request } from 'node:http';
const root = pathToFileURL(resolve(process.argv[2]) + '/');
const pkg = JSON.parse(await readFile(new URL('package.json', root)));
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
