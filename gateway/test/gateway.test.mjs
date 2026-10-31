import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { generateKeyPairSync, randomBytes, createHash, sign } from 'node:crypto';
import { isoCBOR } from '@simplewebauthn/server/helpers';
import { openStore } from '../src/store.mjs';
import { createApp } from '../src/app.mjs';
import { flushJobs } from '../src/push.mjs';
import { routingEvent, apply } from '../../plugins/pocket-notify/index.mjs';
const origin = 'https://dsh.example.com';
const secret = 'test-only-secret-'.repeat(3);
const digest = value => createHash('sha256').update(value).digest();
async function fixture(t, overrides = {}) {
  const db = openStore(':memory:');
  const pocket = createApp({ db, origin, upstream: 'http://127.0.0.1:3000', bootstrapSecret: secret, eventSecret: secret, ...overrides });
  const server = createServer(pocket.app);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { pocket.close(); server.closeAllConnections(); server.close(); db.close(); });
  const call = async (path, body, options = {}) => {
    const { headers, ...rest } = options;
    return new Promise((resolve, reject) => {
      const req = request({ hostname: '127.0.0.1', port: server.address().port, path,
        method: body === undefined ? 'GET' : 'POST', ...rest,
        headers: { host: 'dsh.example.com', origin, 'content-type': 'application/json', ...(body === undefined ? {} : { 'content-length': Buffer.byteLength(JSON.stringify(body)) }), ...headers } }, res => {
        const chunks = [];
        res.on('data', value => chunks.push(value));
        res.on('end', () => {
          const data = Buffer.concat(chunks).toString();
          resolve({ status: res.statusCode,
            headers: { get: name => Array.isArray(res.headers[name]) ? res.headers[name].join(', ') : res.headers[name], getSetCookie: () => res.headers['set-cookie'] || [] },
            text: async () => data, json: async () => JSON.parse(data) });
        });
      });
      req.on('error', reject);
      req.end(body === undefined ? undefined : JSON.stringify(body));
    });
  };
  return { db, call, pocket };
}
const cookies = response => response.headers.getSetCookie().map(s => s.split(';')[0]).join('; ');

test('requires explicit no-auth opt-in and rejects insecure public origins', () => {
  const db = openStore(':memory:');
  try {
    assert.throws(() => createApp({ db, origin, upstream: 'http://127.0.0.1:3000', mode: 'none', eventSecret: secret }));
    assert.throws(() => createApp({ db, origin: 'http://dsh.example.com', upstream: 'http://127.0.0.1:3000', eventSecret: secret }));
  } finally { db.close(); }
});

test('Host/Origin checks, authentication and launch-token isolation', async t => {
  const { call } = await fixture(t);
  assert.equal((await call('/pocket/api/state', undefined, { headers: { host: 'other.example.com' } })).status, 421);
  assert.equal((await call('/api', {}, { headers: { origin: 'https://other.example.com' } })).status, 403);
  assert.equal((await call('/api', {})).status, 401);
  assert.equal((await call('/', undefined)).status, 302);
  assert.equal((await call('/pocket/api/auth/none', {})).status, 403);
  assert.equal((await call('/pocket/api/device', { id: 'device_1234567890', token: 'x'.repeat(32) })).status, 401);
  assert.equal((await call('/pocket/vendor.js')).status, 200);
  assert.equal((await call('/pocket/api/auth/options', { register: true, secret: 'wrong' })).status, 403);
  assert.equal((await call('/pocket/api/events', { id: 'evt', sessionId: 'session', code: 'run.completed' })).status, 401);
});

test('gateway state reports only a bounded plugin version', async t => {
  const valid = await fixture(t, { pluginVersion: '0.3.5' });
  const state = await valid.call('/pocket/api/state');
  assert.equal(state.status, 200);
  assert.equal((await state.json()).pluginVersion, '0.3.5');

  const invalid = await fixture(t, { pluginVersion: 'not a version\nheader' });
  assert.equal((await (await invalid.call('/pocket/api/state')).json()).pluginVersion, '');
});

test('real ES256 Passkey registration, login, wrong origin and replay rejection', async t => {
  const { db, call } = await fixture(t);
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwk = publicKey.export({ format: 'jwk' });
  const credentialId = randomBytes(32);
  const id = credentialId.toString('base64url');
  const cose = isoCBOR.encode(new Map([[1, 2], [3, -7], [-1, 1], [-2, new Uint8Array(Buffer.from(jwk.x, 'base64url'))], [-3, new Uint8Array(Buffer.from(jwk.y, 'base64url'))]]));
  const registration = await call('/pocket/api/auth/options', { register: true, secret });
  assert.equal(registration.status, 200);
  const ceremonyCookie = cookies(registration);
  const options = await registration.json();
  const clientDataJSON = Buffer.from(JSON.stringify({ type: 'webauthn.create', challenge: options.options.challenge, origin }));
  const length = Buffer.alloc(2); length.writeUInt16BE(credentialId.length);
  const authData = Buffer.concat([digest('dsh.example.com'), Buffer.from([0x45]), Buffer.alloc(4), Buffer.alloc(16), length, credentialId, cose]);
  const attestationObject = isoCBOR.encode(new Map([['fmt', 'none'], ['authData', new Uint8Array(authData)], ['attStmt', new Map()]]));
  const registered = await call('/pocket/api/auth/verify', { id: options.id, response: {
    id, rawId: id, type: 'public-key', response: { clientDataJSON: clientDataJSON.toString('base64url'), attestationObject: Buffer.from(attestationObject).toString('base64url'), transports: ['internal'] }, clientExtensionResults: {}
  } }, { headers: { cookie: ceremonyCookie } });
  assert.equal(registered.status, 200, await registered.text());
  assert.match(cookies(registered), /pocket=/);
  assert.match(registered.headers.get('set-cookie'), /HttpOnly/);
  assert.match(registered.headers.get('set-cookie'), /Secure/);
  assert.equal(db.prepare('SELECT count(*) AS n FROM credentials').get().n, 1);
  assert.equal((await call('/pocket/api/auth/options', { register: true, secret })).status, 403);
  const login = async (clientOrigin = origin) => {
    const result = await call('/pocket/api/auth/options', {});
    const challengeCookie = cookies(result);
    const value = await result.json();
    const data = Buffer.from(JSON.stringify({ type: 'webauthn.get', challenge: value.options.challenge, origin: clientOrigin }));
    const counter = Buffer.alloc(4); counter.writeUInt32BE(1);
    const authenticatorData = Buffer.concat([digest('dsh.example.com'), Buffer.from([0x05]), counter]);
    const signature = sign('sha256', Buffer.concat([authenticatorData, digest(data)]), privateKey);
    const payload = { id: value.id, response: { id, rawId: id, type: 'public-key', response: { clientDataJSON: data.toString('base64url'), authenticatorData: authenticatorData.toString('base64url'), signature: signature.toString('base64url'), userHandle: null }, clientExtensionResults: {} } };
    return { payload, challengeCookie };
  };
  const wrong = await login('https://other.example.com');
  assert.equal((await call('/pocket/api/auth/verify', wrong.payload, { headers: { cookie: wrong.challengeCookie } })).status, 401);
  const good = await login();
  assert.equal((await call('/pocket/api/auth/verify', good.payload)).status, 400); // missing browser binding consumes challenge
  const final = await login();
  const response = await call('/pocket/api/auth/verify', final.payload, { headers: { cookie: final.challengeCookie } });
  assert.equal(response.status, 200, await response.text());
  assert.equal(db.prepare('SELECT counter FROM credentials').get().counter, 1);
  assert.equal((await call('/pocket/api/auth/verify', final.payload, { headers: { cookie: final.challengeCookie } })).status, 400);
});

test('device binding, event deduplication, outbox retry and logout revocation', async t => {
  const { db, call } = await fixture(t, { mode: 'none', allowNoAuth: true, pushConfigured: true });
  const login = await call('/pocket/api/auth/none', {});
  const cookie = cookies(login);
  const device = { id: 'device_1234567890', token: 'opaque-test-token-123456789' };
  assert.equal((await call('/pocket/api/device', device, { headers: { cookie } })).status, 200);
  const other = cookies(await call('/pocket/api/auth/none', {}));
  assert.equal((await call('/pocket/api/device', device, { headers: { cookie: other } })).status, 409);
  const event = { id: 'session:1:run.completed', sessionId: 'session', code: 'run.completed', body: 'private conversation' };
  const headers = { authorization: 'Bearer ' + secret };
  assert.equal((await call('/pocket/api/events', event, { headers })).status, 200);
  assert.equal((await call('/pocket/api/events', event, { headers })).status, 200);
  assert.equal(db.prepare('SELECT count(*) AS n FROM jobs').get().n, 1);
  assert.doesNotMatch(db.prepare('SELECT payload FROM jobs').get().payload, /private/);
  await flushJobs(db, async () => { throw Error('offline'); });
  assert.equal(db.prepare('SELECT attempts FROM jobs').get().attempts, 1);
  db.prepare('UPDATE jobs SET due = 0').run();
  let delivered = 0;
  await flushJobs(db, async () => { delivered++; });
  assert.equal(delivered, 1);
  await call('/pocket/api/events', { ...event, id: 'second' }, { headers });
  await call('/pocket/api/logout', {}, { headers: { cookie } });
  await flushJobs(db, async () => { delivered++; });
  assert.equal(delivered, 1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM devices').get().n, 0);
  assert.equal(db.prepare('SELECT count(*) AS n FROM jobs').get().n, 0);
});

test('tiered notification matrix validates, filters and carries only routing metadata', async t => {
  const { db, call } = await fixture(t, { mode: 'none', allowNoAuth: true, pushConfigured: true });
  const cookie = cookies(await call('/pocket/api/auth/none', {}));
  const device = {
    id: 'device_tiered_123456',
    token: 'opaque-tiered-token-123456',
    notifications: {
      version: 1,
      approval: 'standard',
      failed: 'standard',
      completed: 'quiet',
      connection: 'off'
    }
  };
  assert.equal((await call('/pocket/api/device', device, { headers: { cookie } })).status, 200);
  const headers = { authorization: 'Bearer ' + secret };
  const event = { id: 'tiered:1:run.completed', sessionId: 'session-tiered', code: 'run.completed', title: '短标题' };
  assert.equal((await call('/pocket/api/events', event, { headers })).status, 200);
  const payload = JSON.parse(db.prepare('SELECT payload FROM jobs').get().payload);
  assert.equal(payload.version, 1);
  assert.equal(payload.eventId, event.id);
  assert.equal(payload.category, 'completed');
  assert.equal(payload.level, 'quiet');
  assert.equal(payload.sessionId, event.sessionId);
  assert.equal(payload.title, event.title);
  assert.equal(payload.body, undefined);

  device.notifications.completed = 'off';
  assert.equal((await call('/pocket/api/device', device, { headers: { cookie } })).status, 200);
  assert.equal((await call('/pocket/api/events', { ...event, id: 'tiered:2:run.completed' }, { headers })).status, 200);
  assert.equal(db.prepare('SELECT count(*) AS n FROM jobs').get().n, 1);

  device.notifications.completed = 'loud';
  assert.equal((await call('/pocket/api/device', device, { headers: { cookie } })).status, 400);
});

test('plugin routes real Harness events without message content; dispose aborts network', () => {
  const session = { id: 'session' };
  assert.deepEqual(routingEvent(session, { type: 'turn/end', seq: 4, data: { reason: { kind: 'completed' }, private: 'secret' } }), { id: 'session:4:run.completed', sessionId: 'session', code: 'run.completed', seq: 4 });
  assert.equal(routingEvent(session, { type: 'turn/end', seq: 5, data: { reason: { kind: 'cancelled' } } }).code, 'run.stopped');
  assert.equal(routingEvent(session, { type: 'assistant/message' }), null);
  assert.equal(routingEvent(session, { type: 'approval/asked', seq: 9, data: { id: 'approval-id' } }).code, 'permission.required');
  const listeners = new Map();
  const oldSecret = process.env.POCKET_EVENT_SECRET;
  process.env.POCKET_EVENT_SECRET = secret;
  try {
    apply({ on: (name, fn) => listeners.set(name, fn) }, { endpoint: 'https://dsh.example.com/pocket/api/events' });
    assert.ok(listeners.has('session/event'));
    listeners.get('dispose')();
  } finally {
    if (oldSecret === undefined) delete process.env.POCKET_EVENT_SECRET;
    else process.env.POCKET_EVENT_SECRET = oldSecret;
  }
});

test('reverse proxy preserves POST streams and isolates upstream cookies', async t => {
  let observed;
  const upstream = createServer((req, res) => {
    const chunks = [];
    req.on('data', value => chunks.push(value));
    req.on('end', () => {
      observed = { headers: req.headers, body: Buffer.concat(chunks).toString() };
      res.setHeader('Set-Cookie', 'harness-secret=never-forward');
      res.end('stream-response');
    });
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  t.after(() => { upstream.closeAllConnections(); upstream.close(); });
  const { call } = await fixture(t, { mode: 'none', allowNoAuth: true,
    upstream: `http://127.0.0.1:${upstream.address().port}`, upstreamCookie: 'harness=server-only' });
  const response = await call('/api', { message: 'streamed-payload' }, { headers: { cookie: 'pocket=client', authorization: 'Bearer client' } });
  assert.equal(response.status, 200);
  assert.equal(await response.text(), 'stream-response');
  assert.equal(observed.body, '{"message":"streamed-payload"}');
  assert.equal(observed.headers.cookie, 'harness=server-only');
  assert.equal(observed.headers.authorization, undefined);
  assert.equal(observed.headers.origin, `http://127.0.0.1:${upstream.address().port}`);
  assert.equal(response.headers.get('set-cookie'), undefined);
  assert.equal((await call('/?token=client-supplied')).status, 403);
});

test('WebSocket upgrade denies unauthenticated and foreign-origin clients', async t => {
  const { pocket } = await fixture(t);
  let denied = 0;
  pocket.upgrade({ headers: { host: 'dsh.example.com', origin }, url: '/api' }, { destroy: () => { denied++; } }, Buffer.alloc(0));
  pocket.upgrade({ headers: { host: 'dsh.example.com', origin: 'https://other.example.com' }, url: '/api' }, { destroy: () => { denied++; } }, Buffer.alloc(0));
  assert.equal(denied, 2);
});

test('SQLite outbox survives restart and removes expired deliveries', async t => {
  const { mkdtemp, rm } = await import('node:fs/promises');
  const { join } = await import('node:path');
  const { tmpdir } = await import('node:os');
  const directory = await mkdtemp(join(tmpdir(), 'pocket-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const filename = join(directory, 'queue.sqlite');
  let db = openStore(filename);
  db.prepare('INSERT INTO devices VALUES (?,?,?)').run('device', 'owner', 'test-token');
  const add = db.prepare('INSERT INTO jobs(device,payload,due,expires) VALUES (?,?,?,?)');
  add.run('device', '{"code":"run.completed","sessionId":"session"}', 0, Date.now() + 60000);
  add.run('device', '{}', 0, 1);
  db.close();
  db = openStore(filename);
  try {
    let delivered = 0;
    await flushJobs(db, async () => { delivered++; });
    assert.equal(delivered, 1);
    assert.equal(db.prepare('SELECT count(*) AS n FROM jobs').get().n, 0);
  } finally { db.close(); }
});

test('overview tracks concurrent approvals, ignores late events and requires authentication', async t => {
  const locked = await fixture(t);
  assert.equal((await locked.call('/pocket/api/overview')).status, 401);
  const { db, call } = await fixture(t, { mode: 'none', allowNoAuth: true });
  const publish = async (seq, code, approvalId) => {
    const response = await call('/pocket/api/events', { id: `session:${seq}:${code}`, sessionId: 'session', seq, code, ...(approvalId ? { approvalId } : {}) }, { headers: { authorization: 'Bearer ' + secret } });
    assert.equal(response.status, 200);
  };
  const overview = async () => (await call('/pocket/api/overview')).json();
  db.prepare('INSERT INTO devices VALUES (?,?,?)').run('overview-device', 'owner', 'token');
  await publish(0, 'run.started');
  assert.equal(db.prepare('SELECT count(*) AS n FROM jobs').get().n, 0);
  assert.equal((await overview()).running, 1);
  await publish(1, 'permission.required', 'one');
  await publish(2, 'permission.required', 'two');
  assert.equal((await overview()).waiting, 1);
  await publish(3, 'permission.resolved', 'one');
  assert.equal((await overview()).waiting, 1);
  await publish(4, 'permission.resolved', 'two');
  assert.equal(db.prepare('SELECT count(*) AS n FROM jobs').get().n, 0, 'resolved approval reminders must be revoked');
  assert.equal((await overview()).running, 1);
  await publish(6, 'run.completed');
  await publish(5, 'permission.required', 'late');
  const result = await overview();
  assert.equal(result.completed, 1);
  assert.equal(result.waiting, 0);
  assert.equal(result.running, 0);
  assert.equal('sessionId' in result, false);
  assert.equal(db.prepare('SELECT count(*) AS n FROM pending_actions').get().n, 0);
  await publish(7, 'run.started');
  await publish(8, 'run.stopped');
  assert.equal((await overview()).running, 0);
  assert.equal((await call('/pocket/api/events', { id: 'bad', sessionId: 'session', code: 'run.started', seq: -1 }, { headers: { authorization: 'Bearer ' + secret } })).status, 400);
});

test('plugin retries preserve per-session event order before projection', async t => {
  const listeners = new Map();
  const originalSecret = process.env.POCKET_EVENT_SECRET;
  process.env.POCKET_EVENT_SECRET = secret;
  t.after(() => { if (originalSecret === undefined) delete process.env.POCKET_EVENT_SECRET; else process.env.POCKET_EVENT_SECRET = originalSecret; });
  let now = Date.now();
  let tick;
  const calls = [];
  t.mock.method(Date, 'now', () => now);
  t.mock.method(globalThis, 'setInterval', callback => { tick = callback; return { unref() {} }; });
  t.mock.method(globalThis, 'clearInterval', () => {});
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    const event = JSON.parse(options.body); calls.push(event.seq);
    if (calls.length === 1) throw Error('offline');
    return new Response('{}', { status: 200 });
  });
  apply({ on: (name, fn) => listeners.set(name, fn) }, { endpoint: 'https://dsh.example.com/pocket/api/events' });
  const session = { id: 'session' };
  listeners.get('session/event')(session, { type: 'turn/start', seq: 0, data: {} });
  await new Promise(setImmediate);
  listeners.get('session/event')(session, { type: 'approval/asked', seq: 1, data: { id: 'approval' } });
  await new Promise(setImmediate);
  assert.deepEqual(calls, [0], 'later state must wait for failed earlier state');
  now += 10000;
  tick();
  await new Promise(setImmediate);
  assert.deepEqual(calls, [0, 0, 1]);
  listeners.get('dispose')();
});

test('native and compatibility registrations share tokens without crossing login sessions', async t => {
  const {db,call}=await fixture(t,{mode:'none',allowNoAuth:true,pushConfigured:true});
  const owner=cookies(await call('/pocket/api/auth/none',{}));
  const other=cookies(await call('/pocket/api/auth/none',{}));
  const token='same-device-token-123456789';
  assert.equal((await call('/pocket/api/device',{id:'old-device-12345678',token},{headers:{cookie:owner}})).status,200);
  assert.equal((await call('/pocket/api/device',{id:'native-device-123456',token},{headers:{cookie:owner}})).status,200);
  assert.equal(db.prepare('SELECT count(*) AS n FROM devices').get().n,1);
  assert.equal((await call('/pocket/api/device',{id:'other-device-123456',token},{headers:{cookie:other}})).status,409);
  assert.equal((await call('/pocket/api/device',{allForSession:true},{method:'DELETE',headers:{cookie:other}})).status,200);
  assert.equal(db.prepare('SELECT count(*) AS n FROM devices').get().n,1);
  await call('/pocket/api/device',{allForSession:true},{method:'DELETE',headers:{cookie:owner}});
  assert.equal(db.prepare('SELECT count(*) AS n FROM devices').get().n,0);
});

test('notification tiers migrate legacy booleans and filter completion, failure and approval independently', async t => {
  const { db, call } = await fixture(t, { mode: 'none', allowNoAuth: true, pushConfigured: true });
  const cookie = cookies(await call('/pocket/api/auth/none', {}));
  const id = 'tier-device-123456';
  const token = 'tier-token-123456789';
  assert.equal((await call('/pocket/api/device', {
    id, token, notifications: { completed: false, failed: true, approval: true }
  }, { headers: { cookie } })).status, 200);
  assert.deepEqual(
    JSON.parse(db.prepare('SELECT notifications FROM device_preferences WHERE device=?').get(id).notifications),
    { completed: 'off', failed: 'standard', approval: 'standard', connection: 'off' });

  const publish = async (eventId, seq, code, approvalId) => {
    const response = await call('/pocket/api/events', {
      id: eventId, sessionId: 'tier-session', seq, code, ...(approvalId ? { approvalId } : {})
    }, { headers: { authorization: 'Bearer ' + secret } });
    assert.equal(response.status, 200);
  };
  await publish('tier:completed', 1, 'run.completed');
  assert.equal(db.prepare('SELECT count(*) AS n FROM jobs').get().n, 0,
    'an off category must not enqueue work');
  await publish('tier:failed', 2, 'run.failed');
  await publish('tier:approval', 3, 'permission.required', 'tier-approval');
  const jobs = db.prepare('SELECT payload FROM jobs ORDER BY id').all().map(row => JSON.parse(row.payload));
  assert.equal(jobs.length, 2);
  assert.deepEqual(jobs.map(job => [job.category, job.level]), [
    ['failed', 'standard'],
    ['approval', 'standard']
  ]);
  assert.ok(jobs.every(job => job.version === 1 && job.eventId && !('message' in job)));

  assert.equal((await call('/pocket/api/device', {
    id, token, notifications: { completed: 'quiet', failed: 'prominent', approval: 'invalid', connection: 'off' }
  }, { headers: { cookie } })).status, 400);
});
