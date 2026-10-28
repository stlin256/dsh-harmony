import http from 'node:http';
import * as oidc from 'openid-client';
import { configuration } from './config.mjs';
import { Store, random } from './store.mjs';
import { Harness } from './harness.mjs';
import { Proxy } from './proxy.mjs';
import { cookies, cookie, SESSION_COOKIE, FLOW_COOKIE, reply, redirect, requestURL, originOK, landing } from './http.mjs';

process.umask(0o077);
const config = configuration(), store = new Store(config), harness = new Harness(config);
const proxy = new Proxy(config, store, harness);
let discovery, discovered;
async function provider() {
  if (discovered) return discovered;
  if (!discovery) discovery = oidc.discovery(config.issuer, config.clientId, config.clientSecret,
    oidc.ClientSecretBasic(config.clientSecret)).then(value => { discovered = value; return value; }).finally(() => { discovery = null; });
  return discovery;
}
function session(request) { return store.session(cookies(request)[SESSION_COOKIE], true); }
let loginWindow = Date.now(), loginCount = 0;
function loginLimit() {
  const now = Date.now();
  if (now - loginWindow > 60000) { loginWindow = now; loginCount = 0; }
  return ++loginCount <= 30;
}
async function handle(request, response) {
  const url = requestURL(request, config);
  if (url.pathname === '/_gateway/health' && request.method === 'GET') {
    reply(response, 200, JSON.stringify({ status: 'running' }), 'application/json'); return;
  }
  if (url.pathname === '/_gateway/login' && request.method === 'GET') {
    if (!loginLimit(request)) { reply(response, 429, 'Try again later'); return; }
    const providerConfig = await provider();
    const state = oidc.randomState(), nonce = oidc.randomNonce(), binding = random();
    const verifier = oidc.randomPKCECodeVerifier();
    store.prune(); store.newFlow(state, binding, verifier, nonce);
    const target = oidc.buildAuthorizationUrl(providerConfig, {
      redirect_uri: new URL('/_gateway/callback', config.publicUrl).href,
      scope: 'openid profile email', response_type: 'code', state, nonce,
      code_challenge: await oidc.calculatePKCECodeChallenge(verifier), code_challenge_method: 'S256',
      prompt: 'login',
    });
    redirect(response, target.href, cookie(FLOW_COOKIE, binding, 600000)); return;
  }
  if (url.pathname === '/_gateway/callback' && request.method === 'GET') {
    const flow = store.takeFlow(url.searchParams.get('state'), cookies(request)[FLOW_COOKIE]);
    response.setHeader('Set-Cookie', cookie(FLOW_COOKIE, '', 0));
    if (!flow) { reply(response, 401, 'Login expired or browser binding failed. Start again.'); return; }
    const tokens = await oidc.authorizationCodeGrant(await provider(), url, {
      pkceCodeVerifier: flow.verifier, expectedState: url.searchParams.get('state'), expectedNonce: flow.nonce,
      idTokenExpected: true,
    });
    const claims = tokens.claims();
    if (!claims?.sub || !config.subjects.has(claims.sub)) { reply(response, 403, 'This account is not allowed'); return; }
    const old = store.session(cookies(request)[SESSION_COOKIE]); if (old) store.revoke(old.id);
    const token = store.create(claims.sub, (request.headers['user-agent'] || 'unknown').slice(0, 200));
    redirect(response, '/', [cookie(FLOW_COOKIE, '', 0), cookie(SESSION_COOKIE, token, config.maxAge)]); return;
  }
  const current = session(request);
  if (url.pathname === '/_gateway/logout' && request.method === 'POST') {
    if (!current || !originOK(request, config)) { reply(response, 403, 'Logout rejected'); return; }
    store.revoke(current.id); redirect(response, '/', cookie(SESSION_COOKIE, '', 0)); return;
  }
  if (url.pathname === '/_gateway/session' && request.method === 'GET') {
    if (!current) { reply(response, 401, 'Authentication required'); return; }
    reply(response, 200, JSON.stringify({ authenticated: true, createdAt: current.created,
      expiresAt: current.expires, idleExpiresAt: current.seen + config.idleAge }), 'application/json'); return;
  }
  if (url.pathname.startsWith('/_gateway/')) { reply(response, 404, 'Not found'); return; }
  if (!current) {
    if (url.pathname === '/' && ['GET','HEAD'].includes(request.method)) reply(response, 200, landing(), 'text/html; charset=utf-8');
    else reply(response, 401, 'Authentication required');
    return;
  }
  await proxy.http(request, response, current);
}
const server = http.createServer((request, response) => {
  handle(request, response).catch(() => {
    // Never log authorization codes, launch URLs, upstream cookies, or raw exceptions.
    if (!response.headersSent) reply(response, 503, 'Access service temporarily unavailable. Try signing in again.');
    else response.destroy();
    console.error(JSON.stringify({ event: 'request_failed', at: new Date().toISOString() }));
  });
});
server.on('upgrade', (request, socket, head) => {
  (async () => {
    requestURL(request, config);
    const current = session(request);
    if (!current) { socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); return; }
    await proxy.websocket(request, socket, head, current);
  })().catch(() => socket.destroy());
});
server.on('clientError', (_error, socket) => socket.destroy());
// Check the transport peer, never a client-supplied forwarding header.
server.on('connection', (socket) => {
  if (config.trustedProxy && socket.remoteAddress !== config.trustedProxy) socket.destroy();
});
server.requestTimeout = 300000; server.headersTimeout = 15000;
server.listen(config.port, config.host, () => console.log(JSON.stringify({ event: 'gateway_started' })));
const cleanup = setInterval(() => store.prune(), 60000); cleanup.unref();
function stop() { clearInterval(cleanup); proxy.close(); server.close(() => { store.close(); process.exit(0); }); setTimeout(() => process.exit(1), 5000).unref(); }
process.on('SIGTERM', stop); process.on('SIGINT', stop);
