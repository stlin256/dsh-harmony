import { createServer } from 'node:http';
import { openStore } from './store.mjs';
import { createApp } from './app.mjs';
import { createPushSender, flushJobs } from './push.mjs';

const env = process.env;
// Exchange the local Harness launch token once. Its cookie is never sent to the app.
async function exchange() {
  if (!env.UPSTREAM_LAUNCH_URL) return env.UPSTREAM_COOKIE || '';
  const launch = new URL(env.UPSTREAM_LAUNCH_URL);
  if (launch.origin !== new URL(env.UPSTREAM).origin || !launch.searchParams.get('token')) throw Error('Launch URL must match UPSTREAM and contain a token');
  const response = await fetch(launch, { redirect: 'manual', signal: AbortSignal.timeout(10000) });
  const cookie = response.headers.getSetCookie().map(value => value.split(';')[0]).join('; ');
  if (response.status !== 303 || !cookie) throw Error('Harness launch token exchange failed');
  return cookie;
}
const db = openStore(env.DATA_FILE || './data/pocket.sqlite');
const send = createPushSender(env.HUAWEI_SERVICE_ACCOUNT, env.HUAWEI_CATEGORY || 'MARKETING', env.HUAWEI_TEST_MESSAGE !== 'false');
const pocket = createApp({ db, origin: env.PUBLIC_ORIGIN, upstream: env.UPSTREAM,
  upstreamCookie: env.AUTH_MODE === 'proxy' ? '' : await exchange(), mode: env.AUTH_MODE || 'passkey', allowNoAuth: env.ALLOW_NO_AUTH === 'true',
  bootstrapSecret: env.BOOTSTRAP_SECRET, eventSecret: env.EVENT_SECRET, pushConfigured: !!send,
  proxySecret: env.PROXY_SECRET, authOrigin: env.AUTH_ORIGIN || '' });
const server = createServer(pocket.app);
server.on('upgrade', (req, socket, head) => { pocket.upgrade(req, socket, head).catch(() => socket.destroy()); });
let flushing = false;
const tick = async () => {
  if (flushing) return;
  flushing = true;
  try { pocket.cleanup(); await flushJobs(db, send); }
  catch { console.error('Notification queue unavailable'); }
  finally { flushing = false; }
};
const timer = setInterval(tick, 5000);
// Bind to loopback. Put an HTTPS reverse proxy in front, preserving Host and Origin.
server.listen(Number(env.PORT || 8787), '127.0.0.1', () => {
  console.log('DSH Harmony gateway ready');
  void tick();
});
async function shutdown() {
  clearInterval(timer);
  server.close();
  server.closeAllConnections();
  pocket.close();
  // Do not close SQLite underneath an in-flight delivery.
  while (flushing) await new Promise(resolve => setTimeout(resolve, 50));
  db.close();
}
process.once('SIGTERM', () => { void shutdown(); });
process.once('SIGINT', () => { void shutdown(); });
