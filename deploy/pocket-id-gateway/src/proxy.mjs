import http from 'node:http';
import { Transform } from 'node:stream';
import { reply, originOK } from './http.mjs';

const HOP = new Set(['connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailer','transfer-encoding','upgrade']);
function safeHeaders(input, websocket = false) {
  const blocked = new Set([...HOP, ...(input.connection || '').split(',').map(x => x.trim().toLowerCase())]);
  const result = {};
  for (const [key, value] of Object.entries(input)) {
    if (value === undefined || blocked.has(key) || key === 'cookie' || key === 'authorization'
        || key === 'forwarded' || key.startsWith('x-forwarded-') || key.startsWith('x-auth-')
        || key.startsWith('x-authentik-') || key === 'set-cookie') continue;
    result[key] = value;
  }
  if (websocket) { result.connection = 'Upgrade'; result.upgrade = 'websocket'; }
  return result;
}
export class Proxy {
  constructor(config, store, harness) {
    this.config = config; this.store = store; this.harness = harness; this.connections = new Map();
    this.timer = setInterval(() => {
      this.store.prune();
      for (const [resource, id] of this.connections) if (!this.store.byId(id)) resource.destroy();
    }, 15000); this.timer.unref();
  }
  track(resource, id) {
    this.connections.set(resource, id);
    resource.once('close', () => this.connections.delete(resource));
  }
  upstreamHeaders(request, authCookie, websocket = false) {
    return { ...safeHeaders(request.headers, websocket), host: this.config.publicUrl.host,
      cookie: authCookie, 'x-forwarded-proto': 'https', 'x-forwarded-host': this.config.publicUrl.host };
  }
  async http(request, response, session) {
    if (!['GET','HEAD','OPTIONS'].includes(request.method) && !originOK(request, this.config)) {
      reply(response, 403, 'Origin rejected'); return;
    }
    if (['CONNECT','TRACE'].includes(request.method)) { reply(response, 405, 'Method rejected'); return; }
    const size = Number(request.headers['content-length'] || 0);
    if (!Number.isFinite(size) || size < 0 || size > this.config.uploadLimit) {
      reply(response, 413, 'Request too large'); return;
    }
    const authCookie = await this.harness.cookie();
    if (!this.store.byId(session.id)) throw new Error('Session expired');
    const upstream = http.request(new URL(request.url, this.config.upstream), {
      method: request.method, headers: this.upstreamHeaders(request, authCookie),
    }, incoming => {
      if (incoming.statusCode === 401) {
        this.harness.invalidate(); incoming.resume(); reply(response, 502, 'Upstream authentication is refreshing. Retry the request.'); return;
      }
      const values = safeHeaders(incoming.headers);
      delete values['access-control-allow-origin']; delete values['access-control-allow-credentials'];
      values['cache-control'] = 'no-store'; values['referrer-policy'] = 'no-referrer';
      values['x-content-type-options'] = 'nosniff'; values['x-frame-options'] = 'DENY';
      // Native launch URLs are never forwarded as redirects.
      if (values.location) {
        try {
          const location = new URL(values.location, this.config.publicUrl);
          if (location.origin !== this.config.publicUrl.origin || location.searchParams.has('token')) {
            incoming.resume(); reply(response, 502, 'Unexpected upstream redirect'); return;
          }
        } catch { incoming.resume(); reply(response, 502, 'Invalid upstream redirect'); return; }
      }
      response.writeHead(incoming.statusCode || 502, values);
      this.track(response, session.id); incoming.pipe(response);
      response.once('close', () => incoming.destroy());
    });
    this.track(upstream, session.id);
    let count = 0;
    const limit = new Transform({ transform: (chunk, encoding, done) => {
      count += chunk.length;
      done(count > this.config.uploadLimit ? new Error('Upload limit') : null, chunk);
    }});
    limit.on('error', () => { upstream.destroy(); if (!response.headersSent) reply(response, 413, 'Request too large'); else response.destroy(); });
    upstream.on('error', () => { if (!response.headersSent) reply(response, 503, 'Agent temporarily unavailable'); else response.destroy(); });
    request.once('aborted', () => upstream.destroy());
    response.once('close', () => upstream.destroy());
    request.pipe(limit).pipe(upstream);
  }
  async websocket(request, socket, head, session) {
    if (!originOK(request, this.config) || request.headers.upgrade?.toLowerCase() !== 'websocket') {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return;
    }
    const authCookie = await this.harness.cookie();
    if (!this.store.byId(session.id)) throw new Error('Session expired');
    const upstream = http.request(new URL(request.url, this.config.upstream), {
      headers: this.upstreamHeaders(request, authCookie, true),
    });
    const timeout = setTimeout(() => upstream.destroy(), 10000); timeout.unref();
    upstream.on('upgrade', (response, peer, upstreamHead) => {
      clearTimeout(timeout);
      const values = safeHeaders(response.headers, true);
      socket.write('HTTP/1.1 101 Switching Protocols\r\n' + Object.entries(values).map(([k,v]) => `${k}: ${v}`).join('\r\n') + '\r\n\r\n');
      if (upstreamHead.length) socket.write(upstreamHead);
      if (head.length) peer.write(head);
      this.track(socket, session.id);
      socket.on('data', () => this.store.byId(session.id, true));
      socket.once('close', () => peer.destroy()); peer.once('close', () => socket.destroy());
      peer.on('error', () => socket.destroy()); socket.on('error', () => peer.destroy());
      socket.pipe(peer).pipe(socket);
    });
    upstream.on('response', incoming => {
      clearTimeout(timeout);
      if (incoming.statusCode === 401) this.harness.invalidate();
      incoming.resume(); socket.end('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n');
    });
    upstream.on('error', () => { clearTimeout(timeout); socket.destroy(); });
    socket.once('close', () => upstream.destroy());
    upstream.end();
  }
  close() { clearInterval(this.timer); for (const socket of this.connections.keys()) socket.destroy(); }
}
