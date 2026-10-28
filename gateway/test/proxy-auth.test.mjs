import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { openStore } from '../src/store.mjs';
import { createApp } from '../src/app.mjs';
import { PocketBridge } from '../../deploy/oidc-pocket-bridge.mjs';

const secret = 'proxy-test-only-'.repeat(4);
const origin = 'https://workspace.example.com';
const authOrigin = 'https://identity.example.com';
async function fixture(t) {
  const db = openStore(':memory:');
  const pocket = createApp({ db, origin, upstream: 'http://127.0.0.1:3000', mode: 'proxy', proxySecret: secret,
    authOrigin, eventSecret: secret, pushConfigured: true });
  const backend = createServer(pocket.app);
  await new Promise(resolve => backend.listen(0, '127.0.0.1', resolve));
  const session = { id: 'oidc-session-test-'.repeat(3), expires: Date.now() + 3600000, seen: Date.now() };
  let live = true;
  const bridge = new PocketBridge({ target: `http://127.0.0.1:${backend.address().port}`, secret,
    publicOrigin: origin, authOrigin, idleAge: 3600000, uploadLimit: 1048576,
    cookieFor: async () => 'upstream=server-only', validSession: () => live,
    revokeSession: () => { live = false; }, clearCookie: () => '__Host-hpg_session=; Path=/; Secure; HttpOnly; Max-Age=0' });
  const front = createServer((req, res) => {
    const current = live && req.headers.cookie === 'test=valid' ? session : null;
    bridge.http(req, res, current, new URL(req.url, origin)).catch(() => { res.writeHead(500); res.end(); });
  });
  await new Promise(resolve => front.listen(0, '127.0.0.1', resolve));
  t.after(() => { bridge.close(); pocket.close(); front.closeAllConnections(); backend.closeAllConnections(); front.close(); backend.close(); db.close(); });
  const call = (path, options = {}, direct = false) => new Promise((resolve, reject) => {
    const req = request({ hostname: '127.0.0.1', port: (direct ? backend : front).address().port, path,
      method: options.method || 'GET', headers: { host: 'workspace.example.com', origin, ...options.headers } }, res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => resolve(new Response(Buffer.concat(chunks), { status: res.statusCode, headers: res.headers })));
    });
    req.on('error', reject); req.end(options.body);
  });
  return { call, db };
}
test('OIDC login discovery and redirect preserve the existing identity provider', async t => {
  const { call } = await fixture(t);
  const state = await call('/pocket/api/state');
  assert.equal(state.status, 200);
  assert.deepEqual(await state.json(), { mode: 'proxy', authenticated: false, registered: true, authOrigin, pushConfigured: false });
  const login = await call('/pocket/?mode=passkey');
  assert.equal(login.status, 303); assert.equal(login.headers.get('location'), '/_gateway/login');
  assert.equal((await call('/pocket/api/native/sessions', { headers: { 'x-dsh-session': 'forged', 'x-dsh-proxy-secret': secret } })).status, 401);
});
test('loopback backend requires the adapter secret and verified session, not browser headers', async t => {
  const { call } = await fixture(t);
  assert.equal((await call('/pocket/api/state', {}, true)).status, 403);
  assert.equal((await call('/pocket/api/state', { headers: { 'x-dsh-proxy-secret': 'incorrect' } }, true)).status, 403);
  const state = await call('/pocket/api/state', { headers: { cookie: 'test=valid', 'x-dsh-session': 'forged', 'x-dsh-proxy-secret': 'forged', 'x-dsh-upstream-cookie': 'stolen' } });
  assert.equal(state.status, 200); assert.equal((await state.json()).authenticated, true);
  assert.equal(state.headers.get('x-dsh-proxy-secret'), null);
  const rejected = await call('/pocket/api/overview', { headers: { 'x-dsh-proxy-secret': secret, 'x-dsh-session': 'expired-session-'.repeat(3),
    'x-dsh-session-expires': String(Date.now() - 1), 'x-dsh-upstream-cookie': 'upstream=test' } }, true);
  assert.equal(rejected.status, 401);
});
test('event ingress uses its own bearer secret and logout revokes device ownership and OIDC session', async t => {
  const { call, db } = await fixture(t);
  const event = { id: 'event1', sessionId: 'session1', code: 'run.completed', seq: 1 };
  const eventCall = headers => call('/pocket/api/events', { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(event) });
  assert.equal((await eventCall({})).status, 401);
  assert.equal((await eventCall({ authorization: 'Bearer ' + secret })).status, 200);
  const registered = await call('/pocket/api/device', { method: 'POST', headers: { cookie: 'test=valid', 'content-type': 'application/json' },
    body: JSON.stringify({ id: 'device-test-12345678', token: 'token-test-'.repeat(4) }) });
  assert.equal(registered.status, 200); assert.equal(db.prepare('SELECT count(*) n FROM devices').get().n, 1);
  const logout = await call('/pocket/api/logout', { method: 'POST', headers: { cookie: 'test=valid', 'content-type': 'application/json' }, body: '{}' });
  assert.equal(logout.status, 200); assert.match(logout.headers.get('set-cookie'), /Max-Age=0/);
  assert.equal(db.prepare('SELECT count(*) n FROM devices').get().n, 0);
  assert.equal((await call('/pocket/api/overview', { headers: { cookie: 'test=valid' } })).status, 401);
});
