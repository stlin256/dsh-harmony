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
        headers: { host: 'dsh.example.com', origin, 'content-type': 'application/json', ...headers } }, res => {
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

test('plugin routes real Harness events without message content; dispose aborts network', () => {
  const session = { id: 'session' };
  assert.deepEqual(routingEvent(session, { type: 'turn/end', seq: 4, data: { reason: { kind: 'completed' }, private: 'secret' } }), { id: 'session:4:run.completed', sessionId: 'session', code: 'run.completed' });
  assert.equal(routingEvent(session, { type: 'turn/end', data: { reason: { kind: 'cancelled' } } }), null);
  assert.equal(routingEvent(session, { type: 'assistant/message' }), null);
  assert.equal(routingEvent(session, { type: 'approval/asked', seq: 9 }).code, 'permission.required');
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
