import { randomUUID } from 'node:crypto';
import WebSocket, { WebSocketServer } from 'ws';
import { normalizeFollow, normalizedHistory, sessionIdValid } from './native-protocol.mjs';

export function createNativeHarness({ upstream, upstreamCookie, publicOrigin }) {
  const target = new URL(upstream);
  const wss = new WebSocketServer({ noServer: true, maxPayload: 16384, perMessageDeflate: false });
  async function rpc(method, request, signal) {
    const rpcId = randomUUID();
    const response = await fetch(new URL('/api/session/' + method, target), {
      method: 'POST', redirect: 'error', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(20000)]) : AbortSignal.timeout(20000),
      headers: { 'Content-Type': 'application/json', Origin: target.origin, Cookie: upstreamCookie },
      body: JSON.stringify({ type: 'client-request', rpcId, method: 'session/' + method, payload: { args: method === 'list' ? { _request: request } : { request } } })
    });
    // Bound memory even when an incompatible server returns an HTML page or a huge log.
    const reader = response.body?.getReader();
    let size = 0; const chunks = [];
    if (reader) try {
      while (true) { const next = await reader.read(); if (next.done) break; size += next.value.length;
        if (size > 8 * 1024 * 1024) { await reader.cancel(); throw Error('Native response too large'); }
        chunks.push(next.value); }
    } finally { reader.releaseLock(); }
    if (!response.ok) throw Error('Harness native API unavailable');
    const envelope = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (envelope.type !== 'server-response' || envelope.rpcId !== rpcId || envelope.result?.ok !== true) {
      // Do not relay arbitrary upstream details (which may contain paths or credentials).
      throw Error('Harness rejected this operation; use compatibility mode for details');
    }
    return envelope.result.value;
  }
  function routes(app, requireAuth) {
    app.use('/pocket/api/native', requireAuth);
    const guarded = fn => async (req, res) => {
      const abort = new AbortController();
      res.once('close', () => { if (!res.writableEnded) abort.abort(); });
      try { await fn(req, res, abort.signal); }
      catch { if (!res.headersSent && !res.destroyed) res.status(502).json({ error: '原生接口不可用或操作未确认，请刷新核对；也可切换兼容模式。' }); }
    };
    app.get('/pocket/api/native/sessions', guarded(async (_req, res, signal) => {
      const value = await rpc('list', {}, signal);
      const rows = Array.isArray(value?.items) ? value.items : [];
      res.json({ protocol: 1, truncated: rows.length > 200, items: rows.filter(row => sessionIdValid(row.sessionId)).slice(0, 200).map(row => ({
        id: row.sessionId, title: typeof row.projections?.values?.title === 'string' ? row.projections.values.title.slice(0, 200) : '新会话',
        running: row.running === true, updatedAt: Number.isFinite(row.updatedAt) ? row.updatedAt : 0
      })) });
    }));
    app.post('/pocket/api/native/create', guarded(async (req, res, signal) => {
      // A caller-chosen ID makes a timed-out create recoverable through the list.
      if (!sessionIdValid(req.body?.requestId) || (req.body.cwd !== undefined && (typeof req.body.cwd !== 'string' || req.body.cwd.length > 1024))) return res.sendStatus(400);
      const value = await rpc('create', { sessionId: req.body.requestId, ...(req.body.cwd ? { cwd: req.body.cwd } : {}) }, signal);
      if (!sessionIdValid(value?.sessionId)) throw Error('Invalid session');
      res.json({ id: value.sessionId });
    }));
    app.post('/pocket/api/native/page', guarded(async (req, res, signal) => {
      if (!sessionIdValid(req.body?.sessionId) || !Number.isSafeInteger(req.body.beforeSeq) || req.body.beforeSeq < 0) return res.sendStatus(400);
      const value = await rpc('page', { address: { kind: 'session', sessionId: req.body.sessionId }, beforeSeq: req.body.beforeSeq, maxMessages: 60 }, signal);
      const history = normalizedHistory(value.records);
      res.json({ ...history, hasMore: value.hasMore || history.trimmed, cursor: value.cursor });
    }));
    app.post('/pocket/api/native/prompt', guarded(async (req, res, signal) => {
      const { sessionId, requestId, text } = req.body || {};
      if (!sessionIdValid(sessionId) || !sessionIdValid(requestId) || typeof text !== 'string' || !text.trim() || text.length > 3000) return res.sendStatus(400);
      await rpc('prompt', { sessionId, requestId, mode: 'queue', content: [{ type: 'text', text }] }, signal);
      res.json({ accepted: true });
    }));
    app.post('/pocket/api/native/cancel', guarded(async (req, res, signal) => {
      if (!sessionIdValid(req.body?.sessionId)) return res.sendStatus(400);
      await rpc('cancel', { sessionId: req.body.sessionId }, signal); res.json({ accepted: true });
    }));
  }
  function upgrade(req, socket, head) {
    const id = new URL(req.url, publicOrigin).searchParams.get('sessionId');
    if (!sessionIdValid(id)) { socket.destroy(); return; }
    wss.handleUpgrade(req, socket, head, client => {
      const url = new URL('/api/remote.mux', target); url.protocol = target.protocol === 'https:' ? 'wss:' : 'ws:';
      const upstream = new WebSocket(url, { headers: { Cookie: upstreamCookie, Origin: target.origin },
        handshakeTimeout: 10000, maxPayload: 8 * 1024 * 1024, followRedirects: false });
      let alive = true;
      client.on('pong', () => { alive = true; });
      const heartbeat = setInterval(() => {
        if (!alive) { client.terminate(); return; }
        alive = false; client.ping();
      }, 30000);
      heartbeat.unref();
      const send = value => {
        if (client.readyState !== WebSocket.OPEN) return;
        const text = JSON.stringify(value);
        if (client.bufferedAmount > 2 * 1024 * 1024 || Buffer.byteLength(text) > 2 * 1024 * 1024) { client.close(1013, 'Refresh required'); return; }
        client.send(text);
      };
      const opening = setTimeout(() => { send({ type: 'error', message: '等待会话快照超时，请重新连接' }); client.close(1011); }, 15000);
      opening.unref();
      client.once('close', () => clearTimeout(opening));
      upstream.once('open', () => {
        for (const [streamId, method, request] of [
          ['history', 'follow', { address: { kind: 'session', sessionId: id }, assistantStream: true, maxMessages: 80 }],
          ['state', 'observeState', { sessionId: id }]
        ]) upstream.send(JSON.stringify({ type: 'open', streamId, endpoint: 'session/' + method, payload: { args: { request } } }));
      });
      upstream.on('message', raw => {
        try {
          const frame = JSON.parse(raw.toString());
          if (frame.type === 'error') { send({ type: 'error', message: '实时会话不可用，请重新连接或切换兼容模式' }); client.close(1011); return; }
          if (frame.type === 'end') { client.close(1012, 'Stream ended'); return; }
          if (frame.type !== 'item') return;
          if (frame.streamId === 'state') send({ type: 'state', running: frame.value?.running === true,
            waiting: Array.isArray(frame.value?.pendingInput) && frame.value.pendingInput.length > 0 });
          else if (frame.streamId === 'history') {
            if (frame.value?.type === 'snapshot') clearTimeout(opening);
            const value = normalizeFollow(frame.value); if (value) send(value); }
        } catch { client.close(1011, 'Invalid stream'); }
      });
      client.on('message', () => client.close(1008, 'Read-only channel'));
      client.once('close', () => { clearInterval(heartbeat); upstream.terminate(); });
      client.on('error', () => upstream.terminate());
      upstream.on('error', () => { send({ type: 'error', message: '实时连接失败，请检查连接或切换兼容模式' }); client.close(1011); });
      upstream.once('close', () => { if (client.readyState === WebSocket.OPEN) client.close(1012); });
    });
  }
  return { routes, upgrade, close() { for (const client of wss.clients) client.terminate(); wss.close(); } };
}
