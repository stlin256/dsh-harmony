/** Operator-only read-only session probe using the existing private Harness launch file. */
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
const launch = new URL((await readFile(process.argv[2], 'utf8')).trim());
const origin = launch.origin;
const token = launch.searchParams.get('token');
if (!token) throw Error('Launch credential unavailable');
let cookie = '';
const call = async (path, body) => {
  const response = await fetch(origin + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
    headers: { Origin: origin, Cookie: cookie, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  if (!response.ok) throw Error('Probe rejected: ' + path + ' HTTP ' + response.status);
  return response;
};
const login = await call('/pocket/api/auth/native', { token });
cookie = login.headers.getSetCookie().map(x => x.split(';')[0]).join('; ');
if (!cookie) throw Error('No native cookie');
try {
  const state = await (await call('/pocket/api/state')).json();
  const sessions = await (await call('/pocket/api/native/sessions')).json();
  if (!state.authenticated || sessions.protocol !== 2 || !Array.isArray(sessions.items)) throw Error('Unexpected native response');
  await call('/pocket/api/overview');
  let live = 'no-session';
  if (sessions.items.length) {
    const require = createRequire(resolve(import.meta.dirname, '../gateway/package.json'));
    const WebSocket = require('ws');
    await new Promise((done, reject) => {
      const url = new URL('/pocket/native/live', origin); url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      url.searchParams.set('sessionId', sessions.items[0].id);
      const ws = new WebSocket(url, { headers: { Cookie: cookie, Origin: origin }, handshakeTimeout: 10000 });
      const timeout = setTimeout(() => { ws.terminate(); reject(Error('Live probe timed out')); }, 15000);
      let received = false;
      ws.once('message', data => {
        received = true;
        try {
          const frame = JSON.parse(data.toString());
          if (frame.type === 'error') throw Error('Live probe rejected');
          live = frame.type; clearTimeout(timeout); ws.close(); done();
        } catch (error) { clearTimeout(timeout); ws.terminate(); reject(error); }
      });
      ws.once('error', () => { clearTimeout(timeout); reject(Error('Live probe unavailable')); });
      ws.once('close', code => { if (!received) { clearTimeout(timeout); reject(Error('Live channel closed before data: ' + code)); } });
    });
  }
  console.log(JSON.stringify({ nativeLogin: true, httpNativeMode: state.mode, protocol: sessions.protocol, sessions: sessions.items.length, live, pushConfigured: state.pushConfigured }));
} finally {
  await call('/pocket/api/logout', {});
  const state = await (await call('/pocket/api/state')).json();
  if (state.authenticated) throw Error('Native logout failed');
  console.log(JSON.stringify({ nativeLogout: true }));
}
