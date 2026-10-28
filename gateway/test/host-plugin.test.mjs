import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { apply } from '../../plugins/dsh-harmony/index.mjs';

test('one Harness plugin supports HTTP native token login, session APIs, events and logout without a relay', async t => {
  const temp = await mkdtemp(join(tmpdir(), 'harmony-plugin-'));
  const token = 'native-test-token-'.repeat(3);
  const signed = 'v1.' + Buffer.from(JSON.stringify({ expiresAt: Date.now() + 3600000 })).toString('base64url') + '.testsignature';
  const cookie = 'dsh-auth-test=' + signed;
  let route, cleanup, upstreamCalls = 0;
  const listeners = new Map();
  const connection = {
    requestRejection(req) {
      if (req.headers.origin && req.headers.origin !== origin) return 403;
      return req.headers.cookie === cookie ? undefined : 401;
    },
    authenticatedUrl(base) { const url = new URL(base); url.searchParams.set('token', token); return url.href; },
    authorizeIndex(req, res) {
      if (req.method === 'GET' && new URL(req.url, origin).searchParams.get('token') === token) {
        res.writeHead(303, { 'set-cookie': cookie + '; Path=/; HttpOnly; SameSite=Strict' }); res.end();
      } else { res.writeHead(401, {}); res.end(); }
      return false;
    }
  };
  const server = createServer(async (req, res) => {
    if (req.url.startsWith('/pocket')) return route(req, res);
    if (req.url.startsWith('/?token=')) return connection.authorizeIndex(req, res);
    if (req.url === '/api/session/list' && req.headers.cookie === cookie) {
      upstreamCalls++;
      const chunks = []; for await (const chunk of req) chunks.push(chunk);
      const request = JSON.parse(Buffer.concat(chunks));
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ type: 'server-response', rpcId: request.rpcId, result: { ok: true, value: { items: [{ sessionId: 'real-session', running: false }] } } }));
    } else { res.writeHead(401); res.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const ctx = { connection, webServer: { protocol: 'http:', getOrigin: () => origin,
    register(value) { route = value.handler; return () => {}; }, registerUpgrade() { return () => {}; } },
    on(name, fn) { listeners.set(name, fn); }, effect(factory) { cleanup = factory(); }, logger: { warn() {} } };
  apply(ctx, { dataFile: join(temp, 'state.sqlite') });
  t.after(async () => { await cleanup(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await rm(temp, { recursive: true }); });
  const call = (path, body, headers = {}) => fetch(origin + path, { redirect: 'manual', method: body === undefined ? 'GET' : 'POST',
    headers: { origin, 'content-type': 'application/json', ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
  const state = await (await call('/pocket/api/state')).json();
  assert.equal(state.mode, 'host'); assert.equal(state.authenticated, false);
  assert.equal((await call('/pocket/api/auth/native', { token: 'wrong-token-with-enough-characters' })).status, 401);
  assert.equal((await call('/pocket/api/auth/native', { token }, { origin: 'http://foreign.example' })).status, 400);
  const login = await call('/pocket/api/auth/native', { token });
  assert.equal(login.status, 200); assert.match(login.headers.get('set-cookie'), /dsh-auth-test=/);
  assert.equal((await (await call('/pocket/api/state', undefined, { cookie })).json()).authenticated, true);
  const sessions = await call('/pocket/api/native/sessions', undefined, { cookie });
  assert.equal(sessions.status, 200); assert.equal((await sessions.json()).items[0].id, 'real-session'); assert.equal(upstreamCalls, 1);
  listeners.get('session/event')({ id: 'real-session' }, { type: 'turn/start', seq: 1 });
  const overview = await (await call('/pocket/api/overview', undefined, { cookie })).json();
  assert.equal(overview.running, 1);
  const logout = await call('/pocket/api/logout', {}, { cookie });
  assert.equal(logout.status, 200); assert.match(logout.headers.get('set-cookie'), /Max-Age=0/);
  assert.equal((await call('/pocket/api/native/sessions', undefined, { cookie })).status, 401);
});
