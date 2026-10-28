import http from 'node:http';
import { Transform } from 'node:stream';

/** Adapter for an existing authenticated OIDC gateway. No browser credential is trusted here. */
export class PocketBridge {
  constructor({ target, secret, publicOrigin, authOrigin, idleAge, uploadLimit, cookieFor, validSession, revokeSession, clearCookie }) {
    this.target = new URL(target);
    if (this.target.protocol !== 'http:' || !['127.0.0.1', '[::1]'].includes(this.target.hostname) ||
        this.target.pathname !== '/' || this.target.search || this.target.hash || this.target.username || this.target.password ||
        typeof secret !== 'string' || secret.length < 32) throw Error('Invalid Pocket bridge configuration');
    Object.assign(this, { secret, publicOrigin, authOrigin, idleAge, uploadLimit, cookieFor, validSession, revokeSession, clearCookie });
    this.connections = new Map();
    this.timer = setInterval(() => {
      for (const [resource, id] of this.connections) if (!this.validSession(id)) resource.destroy();
    }, 5000);
    this.timer.unref();
  }
  owns(path) { return path === '/pocket' || path.startsWith('/pocket/'); }
  track(resource, session) {
    if (!session) return;
    this.connections.set(resource, session.id);
    resource.once('close', () => this.connections.delete(resource));
  }
  async headers(request, session, websocket = false) {
    const headers = {};
    const blocked = new Set(['connection', 'keep-alive', 'proxy-authorization', 'proxy-authenticate', 'te', 'trailer',
      'transfer-encoding', 'upgrade', 'cookie', 'authorization', 'forwarded', 'set-cookie', ...(request.headers.connection || '').toLowerCase().split(',').map(x => x.trim())]);
    for (const [key, value] of Object.entries(request.headers)) {
      if (value !== undefined && !blocked.has(key) && !key.startsWith('x-dsh-') && !key.startsWith('x-auth-') && !key.startsWith('x-forwarded-')) headers[key] = value;
    }
    headers.host = new URL(this.publicOrigin).host;
    headers['x-dsh-proxy-secret'] = this.secret;
    if (session) {
      headers['x-dsh-session'] = session.id;
      headers['x-dsh-session-expires'] = String(Math.min(session.expires, session.seen + this.idleAge));
      if (!this.validSession(session.id)) throw Error('Session expired');
    } else if (request.headers.authorization) headers.authorization = request.headers.authorization;
    if (websocket) { headers.connection = 'Upgrade'; headers.upgrade = 'websocket'; }
    return headers;
  }
  responseHeaders(input) {
    const result = {};
    for (const [key, value] of Object.entries(input)) {
      if (value !== undefined && !['connection', 'transfer-encoding', 'set-cookie', 'keep-alive'].includes(key) && !key.startsWith('x-dsh-')) result[key] = value;
    }
    return result;
  }
  async http(request, response, session, url) {
    if (url.pathname === '/_gateway/logout' && request.method === 'POST' && session && request.headers.origin === this.publicOrigin) {
      // Browser logout must also revoke its Pocket endpoints, even if Harness is down.
      await new Promise(resolve => {
        this.headers(request, session).then(headers => {
          const revoke = http.request(new URL('/pocket/api/logout', this.target), { method: 'POST',
            headers: { ...headers, origin: this.publicOrigin, 'content-type': 'application/json', 'content-length': 2 }, timeout: 5000 }, res => {
            res.resume(); res.once('end', resolve);
          });
          revoke.on('error', resolve); revoke.on('timeout', () => revoke.destroy()); revoke.end('{}');
        }).catch(resolve);
      });
    }
    if (!this.owns(url.pathname)) return false;
    if (!session && url.pathname === '/pocket/api/state' && request.method === 'GET') {
      response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      response.end(JSON.stringify({ mode: 'proxy', authenticated: false, registered: true, authOrigin: this.authOrigin, pushConfigured: false }));
      return true;
    }
    const event = url.pathname === '/pocket/api/events' && request.method === 'POST';
    if (!session && !event) {
      if (url.pathname.startsWith('/pocket/api/') || !['GET', 'HEAD'].includes(request.method)) {
        response.writeHead(401, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        response.end(JSON.stringify({ error: '请先登录工作空间' }));
      } else { response.writeHead(303, { Location: '/_gateway/login', 'Cache-Control': 'no-store' }); response.end(); }
      return true;
    }
    if (!event && !['GET', 'HEAD', 'OPTIONS'].includes(request.method) && request.headers.origin !== this.publicOrigin) {
      response.writeHead(403); response.end('Origin rejected'); return true;
    }
    if (['CONNECT', 'TRACE'].includes(request.method) || Number(request.headers['content-length'] || 0) > this.uploadLimit) {
      response.writeHead(413); response.end('Request rejected'); return true;
    }
    const headers = await this.headers(request, session);
    const upstream = http.request(new URL(request.url, this.target), { method: request.method, headers }, incoming => {
      const values = this.responseHeaders(incoming.headers);
      if (url.pathname === '/pocket/api/logout' && request.method === 'POST' && incoming.statusCode === 200 && session) {
        this.revokeSession(session.id); values['set-cookie'] = this.clearCookie();
      }
      response.writeHead(incoming.statusCode || 502, values);
      incoming.pipe(response); response.once('close', () => incoming.destroy());
    });
    this.track(upstream, session); this.track(response, session);
    let bytes = 0;
    const limit = new Transform({ transform: (chunk, encoding, done) => {
      bytes += chunk.length; done(bytes > this.uploadLimit ? Error('Upload limit') : null, chunk);
    } });
    limit.on('error', () => { upstream.destroy(); response.destroy(); });
    upstream.on('error', () => { if (!response.headersSent) { response.writeHead(503); response.end('Pocket service unavailable'); } else response.destroy(); });
    request.once('aborted', () => upstream.destroy()); response.once('close', () => upstream.destroy());
    request.pipe(limit).pipe(upstream);
    return true;
  }
  async upgrade(request, socket, head, session, url) {
    if (!this.owns(url.pathname)) return false;
    if (!session || url.pathname !== '/pocket/native/live' || request.headers.origin !== this.publicOrigin || request.headers.upgrade?.toLowerCase() !== 'websocket') {
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); return true;
    }
    const upstream = http.request(new URL(request.url, this.target), { headers: await this.headers(request, session, true) });
    const timeout = setTimeout(() => upstream.destroy(), 10000); timeout.unref();
    upstream.on('upgrade', (response, peer, upstreamHead) => {
      clearTimeout(timeout);
      const values = this.responseHeaders(response.headers);
      values.connection = 'Upgrade'; values.upgrade = 'websocket';
      socket.write('HTTP/1.1 101 Switching Protocols\r\n' + Object.entries(values).map(([k,v]) => `${k}: ${v}`).join('\r\n') + '\r\n\r\n');
      if (upstreamHead.length) socket.write(upstreamHead);
      if (head.length) peer.write(head);
      this.track(socket, session);
      socket.once('close', () => peer.destroy()); peer.once('close', () => socket.destroy());
      socket.on('error', () => peer.destroy()); peer.on('error', () => socket.destroy());
      socket.pipe(peer).pipe(socket);
    });
    upstream.on('response', incoming => { clearTimeout(timeout); incoming.resume(); socket.end('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n'); });
    upstream.on('error', () => { clearTimeout(timeout); socket.destroy(); });
    socket.once('close', () => upstream.destroy()); upstream.end();
    return true;
  }
  close() { clearInterval(this.timer); for (const resource of this.connections.keys()) resource.destroy(); }
}
