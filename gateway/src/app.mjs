import express from 'express';
import { createNativeHarness } from './native-harness.mjs';
import { eventCodes, notificationCodes, projectEvent, readOverview } from './overview.mjs';
import httpProxy from 'http-proxy';
import { randomBytes, createHash, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { generateRegistrationOptions, verifyRegistrationResponse, generateAuthenticationOptions, verifyAuthenticationResponse } from '@simplewebauthn/server';

const random = () => randomBytes(32).toString('base64url');
const hash = value => createHash('sha256').update(value).digest('hex');
const equal = (a, b) => {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const left = Buffer.from(a); const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
};
const cookie = req => /(?:^|;\s*)pocket=([A-Za-z0-9_-]{43})(?:;|$)/.exec(req.headers.cookie || '')?.[1];
const SESSION_TTL = 30 * 86400000;

export function createApp({ db, origin, upstream, upstreamCookie = '', mode = 'passkey', allowNoAuth = false, bootstrapSecret, eventSecret, pushConfigured = false }) {
  const publicURL = new URL(origin);
  const target = new URL(upstream);
  if (publicURL.protocol !== 'https:' || publicURL.origin !== origin) throw Error('PUBLIC_ORIGIN must be an HTTPS origin');
  if (!['http:', 'https:'].includes(target.protocol) || target.username || target.password || target.pathname !== '/' || target.search || target.hash) throw Error('UPSTREAM must be an HTTP(S) origin');
  if (!['passkey', 'none'].includes(mode) || (mode === 'none' && !allowNoAuth)) throw Error('No-auth requires explicit ALLOW_NO_AUTH=true');
  if (!eventSecret || eventSecret.length < 32) throw Error('EVENT_SECRET must have at least 32 characters');
  if (mode === 'passkey' && (!bootstrapSecret || bootstrapSecret.length < 32)) throw Error('BOOTSTRAP_SECRET must have at least 32 characters');
  const native = createNativeHarness({ upstream: target.origin, upstreamCookie, publicOrigin: origin });
  const app = express();
  app.disable('x-powered-by');
  const challenges = new Map();
  const sockets = new Map();
  const limits = new Map();
  const proxy = httpProxy.createProxyServer({ target: target.origin, changeOrigin: true, ws: true });
  proxy.on('error', (_error, _req, res) => {
    if (res.writeHead) { if (!res.headersSent) res.writeHead(502); res.end('Harness unavailable'); }
    else res.destroy();
  });
  proxy.on('proxyRes', response => {
    // Backend launch credentials and cookies stay on the server. Never forward an
    // upstream redirect containing its one-time login token to a remote client.
    delete response.headers['set-cookie'];
    const location = response.headers.location;
    if (location) {
      try {
        const url = new URL(location, target.origin);
        if (url.searchParams.has('token') || url.origin !== target.origin) {
          response.statusCode = 502; delete response.headers.location;
        } else response.headers.location = origin + url.pathname + url.search + url.hash;
      } catch { delete response.headers.location; }
    }
  });
  const setCookie = (res, value, maxAge) => res.cookie('pocket', value, { httpOnly: true, secure: true, sameSite: 'strict', path: '/', maxAge });
  function session(req) {
    const id = cookie(req);
    return id && db.prepare('SELECT id FROM sessions WHERE id = ? AND expires > ?').get(hash(id), Date.now())?.id;
  }
  function authenticated(req) { return mode === 'none' || !!session(req); }
  function establish(req, res) {
    const old = session(req);
    const id = random();
    const owner = hash(id);
    if (old) {
      for (const socket of sockets.get(old) || []) socket.destroy();
      db.prepare('UPDATE devices SET owner = ? WHERE owner = ?').run(owner, old);
      db.prepare('DELETE FROM sessions WHERE id = ?').run(old);
    }
    db.prepare('INSERT INTO sessions VALUES (?, ?)').run(owner, Date.now() + SESSION_TTL);
    setCookie(res, id, SESSION_TTL);
  }
  function requireAuth(req, res, next) {
    if (!authenticated(req)) return res.status(401).json({ error: '请先登录' });
    next();
  }
  // Exact Host validation is independent of X-Forwarded-* trust configuration.
  app.use((req, res, next) => {
    if (req.headers.host !== publicURL.host) return res.status(421).end('Untrusted Host');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Frame-Options', 'DENY');
    if (req.path !== '/pocket/api/events' && !['GET', 'HEAD', 'OPTIONS'].includes(req.method) && req.headers.origin !== origin) return res.status(403).end('Untrusted Origin');
    next();
  });
  // Parse only our endpoints: leave the upstream POST/stream bodies untouched.
  app.use('/pocket/api', express.json({ limit: '16kb' }));
  app.use('/pocket/api/auth', (req, res, next) => {
    const now = Date.now();
    // A global bound avoids trusting forwarded IP headers and bounds memory.
    const bucket = Math.floor(now / 60000);
    if (limits.get(bucket) >= 120) return res.status(429).json({ error: '请稍后重试' });
    const count = limits.get(bucket) || 0;
    limits.clear(); limits.set(bucket, count + 1);
    for (const [id, value] of challenges) if (value.expires < now) challenges.delete(id);
    next();
  });
  app.get('/pocket/api/state', (req, res) => {
    res.json({ mode, authenticated: authenticated(req), registered: !!db.prepare('SELECT id FROM credentials LIMIT 1').get(), pushConfigured });
  });
  app.post('/pocket/api/auth/none', (req, res) => {
    if (mode !== 'none') return res.sendStatus(403);
    establish(req, res); res.json({ ok: true });
  });
  app.post('/pocket/api/auth/options', async (req, res) => {
    if (mode !== 'passkey') return res.sendStatus(400);
    const registering = req.body?.register === true;
    const rows = db.prepare('SELECT * FROM credentials').all();
    if (registering && (rows.length || !equal(req.body?.secret, bootstrapSecret))) return res.sendStatus(403);
    if (!registering && !rows.length) return res.status(409).json({ error: '请先注册 Passkey' });
    const options = registering ? await generateRegistrationOptions({ rpName: 'DSH Harmony', rpID: publicURL.hostname,
      userID: new Uint8Array(Buffer.from('dsh-pocket-owner')), userName: 'owner', attestationType: 'none',
      authenticatorSelection: { residentKey: 'required', userVerification: 'required' } }) :
      await generateAuthenticationOptions({ rpID: publicURL.hostname, userVerification: 'required',
        allowCredentials: rows.map(row => ({ id: row.id, transports: JSON.parse(row.transports) })) });
    const id = random();
    // Bind challenge to an independent HttpOnly ceremony cookie; consume on every
    // verification attempt. A ceremony does not establish an authenticated session.
    const binder = random();
    res.cookie('pocket_ceremony', binder, { httpOnly: true, secure: true, sameSite: 'strict', path: '/pocket/api/auth', maxAge: 120000 });
    challenges.set(id, { challenge: options.challenge, registering, binder: hash(binder), expires: Date.now() + 120000 });
    res.json({ id, options });
  });
  app.post('/pocket/api/auth/verify', async (req, res) => {
    const entry = challenges.get(req.body?.id);
    challenges.delete(req.body?.id);
    const binder = /(?:^|;\s*)pocket_ceremony=([A-Za-z0-9_-]{43})(?:;|$)/.exec(req.headers.cookie || '')?.[1];
    if (!entry || entry.expires < Date.now() || !binder || !equal(entry.binder, hash(binder))) return res.sendStatus(400);
    try {
      if (entry.registering) {
        if (db.prepare('SELECT id FROM credentials LIMIT 1').get()) return res.sendStatus(409);
        const result = await verifyRegistrationResponse({ response: req.body.response, expectedChallenge: entry.challenge,
          expectedOrigin: origin, expectedRPID: publicURL.hostname, requireUserVerification: true });
        if (!result.verified || !result.registrationInfo) return res.sendStatus(401);
        if (db.prepare('SELECT id FROM credentials LIMIT 1').get()) return res.sendStatus(409);
        const c = result.registrationInfo.credential;
        db.prepare('INSERT INTO credentials VALUES (?, ?, ?, ?)').run(c.id, Buffer.from(c.publicKey).toString('base64url'), c.counter, JSON.stringify(c.transports || []));
      } else {
        const row = db.prepare('SELECT * FROM credentials WHERE id = ?').get(req.body.response?.id || '');
        if (!row) return res.sendStatus(401);
        const result = await verifyAuthenticationResponse({ response: req.body.response, expectedChallenge: entry.challenge,
          expectedOrigin: origin, expectedRPID: publicURL.hostname, requireUserVerification: true,
          credential: { id: row.id, publicKey: new Uint8Array(Buffer.from(row.publicKey, 'base64url')), counter: row.counter, transports: JSON.parse(row.transports) } });
        if (!result.verified) return res.sendStatus(401);
        db.prepare('UPDATE credentials SET counter = ? WHERE id = ?').run(result.authenticationInfo.newCounter, row.id);
      }
      establish(req, res); res.json({ ok: true });
    } catch { res.status(401).json({ error: 'Passkey 验证失败，请重试' }); }
  });
  app.post('/pocket/api/device', requireAuth, (req, res) => {
    if (!pushConfigured) return res.status(503).json({ error: '服务器未配置 Huawei Push' });
    const owner = session(req);
    if (!owner) return res.status(401).json({ error: '请先点击登录' });
    const { id, token } = req.body || {};
    if (!/^[A-Za-z0-9_-]{16,80}$/.test(id) || typeof token !== 'string' || token.length < 16 || token.length > 4096) return res.sendStatus(400);
    const existing = db.prepare('SELECT id,owner FROM devices WHERE id = ? OR token = ?').all(id, token);
    if (existing.some(row => row.owner !== owner)) return res.status(409).json({ error: '设备已绑定其他登录会话，请先在原会话关闭通知' });
    db.exec('BEGIN IMMEDIATE');
    try {
      db.prepare('DELETE FROM devices WHERE token = ? AND owner = ? AND id != ?').run(token, owner, id);
      db.prepare('INSERT INTO devices VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET token=excluded.token').run(id, owner, token);
      db.exec('COMMIT');
    } catch (error) { db.exec('ROLLBACK'); throw error; }
    res.json({ ok: true });
  });
  app.delete('/pocket/api/device', requireAuth, (req, res) => {
    if (req.body?.allForSession === true) db.prepare('DELETE FROM devices WHERE owner = ?').run(session(req) || '');
    else db.prepare('DELETE FROM devices WHERE id = ? AND owner = ?').run(String(req.body?.id || ''), session(req) || '');
    res.json({ ok: true });
  });
  app.post('/pocket/api/logout', (req, res) => {
    const owner = session(req);
    if (owner) {
      for (const socket of sockets.get(owner) || []) socket.destroy();
      db.prepare('DELETE FROM devices WHERE owner = ?').run(owner);
      db.prepare('DELETE FROM sessions WHERE id = ?').run(owner);
    }
    setCookie(res, '', 0); res.json({ ok: true });
  });
  app.get('/pocket/api/overview', requireAuth, (_req, res) => res.json(readOverview(db)));
  app.post('/pocket/api/events', (req, res) => {
    if (!equal(req.headers.authorization, 'Bearer ' + eventSecret)) return res.sendStatus(401);
    const { id, sessionId, code } = req.body || {};
    if (!/^[A-Za-z0-9_:.-]{1,240}$/.test(id) || !/^[A-Za-z0-9_-]{1,160}$/.test(sessionId) || !eventCodes.includes(code)) return res.sendStatus(400);
    const { seq, approvalId } = req.body;
    if (seq !== undefined && (!Number.isSafeInteger(seq) || seq < 0)) return res.sendStatus(400);
    if (seq !== undefined && code.startsWith('permission.') && (typeof approvalId !== 'string' || !/^[A-Za-z0-9_-]{1,160}$/.test(approvalId))) return res.sendStatus(400);
    const now = Date.now();
    db.exec('BEGIN IMMEDIATE');
    try {
      const inserted = db.prepare('INSERT OR IGNORE INTO events VALUES (?, ?)').run(id, now);
      if (inserted.changes && projectEvent(db, { sessionId, code, seq, approvalId }, now) && notificationCodes.includes(code)) {
        const payload = JSON.stringify({ sessionId, code });
        for (const device of db.prepare('SELECT id FROM devices').all()) {
          db.prepare('INSERT INTO jobs(device,payload,due,expires) VALUES (?,?,?,?)').run(device.id, payload, now, now + 3600000);
        }
      }
      db.exec('COMMIT'); res.json({ ok: true });
    } catch (error) { db.exec('ROLLBACK'); throw error; }
  });
  native.routes(app, requireAuth);
  const publicDir = fileURLToPath(new URL('../public/', import.meta.url));
  app.get('/pocket/vendor.js', (_req, res) => res.sendFile(fileURLToPath(new URL('../node_modules/@simplewebauthn/browser/dist/bundle/index.umd.min.js', import.meta.url))));
  app.use('/pocket', (_req, res, next) => {
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"); next();
  });
  app.use('/pocket', express.static(publicDir, { index: 'index.html' }));
  app.use('/pocket/api', (_req, res) => res.sendStatus(404));
  function prepareProxy(req) {
    req.headers.host = target.host;
    if (req.headers.origin) req.headers.origin = target.origin;
    if (req.headers.referer) req.headers.referer = target.origin + '/';
    req.headers.cookie = upstreamCookie;
    delete req.headers.authorization;
    delete req.headers['x-forwarded-for']; delete req.headers['x-forwarded-host']; delete req.headers['x-forwarded-proto'];
  }
  app.use((req, res) => {
    if (!authenticated(req)) {
      if (req.method === 'GET' && req.accepts('html')) return res.redirect('/pocket/');
      return res.sendStatus(401);
    }
    // Never let a browser provide or exchange a Harness launch token.
    if (new URL(req.url, origin).searchParams.has('token')) return res.sendStatus(403);
    prepareProxy(req); proxy.web(req, res);
  });
  app.use((error, _req, res, _next) => res.status(error.status === 413 ? 413 : 400).json({ error: '请求失败，请检查输入后重试' }));
  function upgrade(req, socket, head) {
    if (req.headers.host !== publicURL.host || req.headers.origin !== origin || !authenticated(req) || new URL(req.url, origin).searchParams.has('token')) { socket.destroy(); return; }
    const owner = session(req);
    const key = owner || 'anonymous';
    if (!sockets.has(key)) sockets.set(key, new Set());
    sockets.get(key).add(socket);
    const expires = owner ? db.prepare('SELECT expires FROM sessions WHERE id = ?').get(owner).expires : Date.now() + SESSION_TTL;
    const expiry = setTimeout(() => socket.destroy(), Math.min(2147483647, expires - Date.now()));
    expiry.unref();
    socket.once('close', () => { clearTimeout(expiry); sockets.get(key)?.delete(socket); if (!sockets.get(key)?.size) sockets.delete(key); });
    if (new URL(req.url, origin).pathname === '/pocket/native/live') {
      if (sockets.get(key).size > 4) { socket.destroy(); return; }
      native.upgrade(req, socket, head);
    } else { prepareProxy(req); proxy.ws(req, socket, head); }
  }
  function cleanup() {
    const now = Date.now();
    db.prepare('DELETE FROM devices WHERE owner IN (SELECT id FROM sessions WHERE expires <= ?)').run(now);
    db.prepare('DELETE FROM sessions WHERE expires <= ?').run(now);
    db.prepare('DELETE FROM events WHERE created < ?').run(now - 7 * 86400000);
    db.prepare('DELETE FROM task_states WHERE updated < ?').run(now - 30 * 86400000);
    db.prepare('DELETE FROM pending_actions WHERE session NOT IN (SELECT session FROM task_states)').run();
  }
  return { app, upgrade, cleanup, close: () => { for (const set of sockets.values()) for (const socket of set) socket.destroy(); native.close(); proxy.close(); } };
}
