import { randomUUID } from 'node:crypto';
import WebSocket, { WebSocketServer } from 'ws';
import { normalizeFollow, normalizedHistory, sessionIdValid } from './native-protocol.mjs';

export function createNativeHarness({ upstream, upstreamCookie, publicOrigin, ownerOf }) {
  const connections = new Map();
  const target = new URL(upstream);
  const wss = new WebSocketServer({ noServer: true, maxPayload: 16384, perMessageDeflate: false });
  async function rpc(method, request, signal) {
    const rpcId = randomUUID();
    const endpoint = method === '$events/result' ? method : method === 'answerQuestion' ? 'userQuestions/answer' : 'session/' + method;
    const response = await fetch(new URL('/api/' + endpoint, target), {
      method: 'POST', redirect: 'error', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(20000)]) : AbortSignal.timeout(20000),
      headers: { 'Content-Type': 'application/json', Origin: target.origin, Cookie: upstreamCookie },
      body: JSON.stringify({ type: 'client-request', rpcId, method: endpoint, payload: { args: method === '$events/result' ? request : method === 'answerQuestion' ? { agent: request.sessionId, callId: request.callId, answer: request.answer } : method === 'list' ? { _request: request } : method === 'modelCatalog' ? {} : { request } } })
    });
    if (!response.ok) throw Error('Harness native API unavailable');
    const envelope = await response.json();
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
      res.json({ protocol: 2, truncated: false, items: rows.filter(row => sessionIdValid(row.sessionId)).map(row => ({
        id: row.sessionId, title: typeof row.projections?.values?.title === 'string' ? row.projections.values.title : '新会话',
        running: row.running === true, updatedAt: Number.isFinite(row.updatedAt) ? row.updatedAt : 0
      })) });
    }));
    app.post('/pocket/api/native/create', guarded(async (req, res, signal) => {
      // A caller-chosen ID makes a timed-out create recoverable through the list.
      if (!sessionIdValid(req.body?.requestId) || (req.body.cwd !== undefined && typeof req.body.cwd !== 'string')) return res.sendStatus(400);
      const value = await rpc('create', { sessionId: req.body.requestId, ...(req.body.cwd ? { cwd: req.body.cwd } : {}), ...(typeof req.body.agentPreset === 'string' && req.body.agentPreset ? { agentPreset: req.body.agentPreset } : {}) }, signal);
      if (!sessionIdValid(value?.sessionId)) throw Error('Invalid session');
      res.json({ id: value.sessionId });
    }));
    app.post('/pocket/api/native/page', guarded(async (req, res, signal) => {
      if (!sessionIdValid(req.body?.sessionId) || !Number.isSafeInteger(req.body.beforeSeq) || req.body.beforeSeq < 0) return res.sendStatus(400);
      const value = await rpc('page', { address: { kind: 'session', sessionId: req.body.sessionId }, beforeSeq: req.body.beforeSeq, ...(Number.isSafeInteger(req.body.throughSeq) ? { throughSeq: req.body.throughSeq } : {}), maxMessages: 60 }, signal);
      const history = normalizedHistory(value.records);
      res.json({ ...history, hasMore: value.hasMore || history.trimmed, cursor: value.cursor, beforeSeq: value.records?.[0]?.event?.seq ?? req.body.beforeSeq, throughSeq: value.cursor });
    }));
    app.post('/pocket/api/native/prompt', guarded(async (req, res, signal) => {
      const { sessionId, requestId, text } = req.body || {};
      if (!sessionIdValid(sessionId) || !sessionIdValid(requestId) || typeof text !== 'string' || (!text.trim() && !req.body.images?.length)) return res.sendStatus(400);
      if (req.body.mode !== undefined && !['queue', 'steer'].includes(req.body.mode)) return res.sendStatus(400);
      if (req.body.images !== undefined && (!Array.isArray(req.body.images) || !req.body.images.every(image =>
        ['image/png','image/jpeg','image/webp','image/gif'].includes(image?.mediaType) && typeof image.data === 'string' && image.data.length > 0 &&
        (image.name === undefined || typeof image.name === 'string')))) return res.sendStatus(400);
      const content = [...(text.trim() ? [{ type: 'text', text }] : []), ...(req.body.images || []).map(image => ({ type: 'image',
        mediaType: image.mediaType, data: image.data, ...(image.name ? { name: image.name } : {}) }))];
      await rpc('prompt', { sessionId, requestId, mode: req.body.mode || 'queue', content }, signal);
      res.json({ accepted: true });
    }));
    app.post('/pocket/api/native/answer', guarded(async (req, res, signal) => {
      const connection = connections.get(req.body?.connectionId);
      const pending = connection?.pending.get(req.body?.eventId);
      if (!connection || connection.owner !== ownerOf(req) || !pending) return res.sendStatus(409);
      if (req.body.engage === true) { clearTimeout(pending.timer); pending.engaged = true; return res.json({ accepted: true }); }
      let outcome;
      if (req.body.delegate === true) outcome = { kind: 'next' };
      else if (pending.event === 'approval/request') {
        if (!['allowed-once', 'rejected'].includes(req.body.value)) return res.sendStatus(400);
        outcome = { kind: 'result', value: req.body.value };
      } else {
        const questions = pending.request.questions;
        const answers = req.body.value?.answers;
        if (!Array.isArray(questions) || !Array.isArray(answers) || answers.length !== questions.length ||
            new Set(answers.map(answer => answer.id)).size !== questions.length ||
            !questions.every(question => {
              const answer = answers.find(item => item.id === question.id);
              return answer && Array.isArray(answer.selected) && answer.selected.every(label => typeof label === 'string' && question.options?.some(option => option.label === label)) &&
                new Set(answer.selected).size === answer.selected.length && (question.multiSelect || answer.selected.length <= 1) &&
                (answer.custom === undefined || typeof answer.custom === 'string') &&
                !(question.intent?.kind === 'approval' && (answer.custom || answer.selected.length !== 1));
            })) return res.sendStatus(400);
        outcome = { kind: 'result', value: { answers } };
      }
      // One user action, one result. Never repeat a potentially accepted decision.
      clearTimeout(pending.timer);
      connection.pending.delete(req.body.eventId);
      if (req.body.delegate === true && pending.request?.wait?.timed === true) connection.cancelWait(req.body.eventId);
      await rpc('$events/result', { clientId: connection.clientId, eventId: req.body.eventId, outcome }, signal);
      connection.send({ type: 'interaction-ended', eventId: req.body.eventId });
      res.json({ accepted: true });
    }));
    app.post('/pocket/api/native/operation', guarded(async (req, res, signal) => {
      const { operation, sessionId } = req.body || {};
      if (operation !== 'modelCatalog' && !sessionIdValid(sessionId)) return res.sendStatus(400);
      let request;
      switch (operation) {
        case 'modelCatalog': request = {}; break;
        case 'answerQuestion':
          if (typeof req.body.callId !== 'string' || !req.body.callId || !Array.isArray(req.body.answer?.answers) ||
              !req.body.answer.answers.every(answer => typeof answer.id === 'string' && Array.isArray(answer.selected) &&
                answer.selected.every(value => typeof value === 'string') && (answer.custom === undefined || typeof answer.custom === 'string'))) return res.sendStatus(400);
          request = { sessionId, callId: req.body.callId, answer: req.body.answer }; break;
        case 'attachment': {
          const ref = req.body.attachment;
          if (!ref || typeof ref.attachmentId !== 'string' || !ref.attachmentId ||
              !['image/png','image/jpeg','image/webp','image/gif'].includes(ref.mediaType) ||
              ![ref.bytes,ref.width,ref.height].every(value => Number.isSafeInteger(value) && value > 0)) return res.sendStatus(400);
          request = { sessionId, attachment: ref }; break;
        }
        case 'state': case 'projections': request = { sessionId }; break;
        case 'rename':
          if (typeof req.body.title !== 'string' || !req.body.title.trim()) return res.sendStatus(400);
          request = { sessionId, title: req.body.title }; break;
        case 'fork':
          if (req.body.atSeq !== undefined && (!Number.isSafeInteger(req.body.atSeq) || req.body.atSeq < 0)) return res.sendStatus(400);
          request = { sessionId, ...(req.body.atSeq === undefined ? {} : { atSeq: req.body.atSeq }), allowMigration: false }; break;
        case 'selectModel':
          if (![req.body.provider, req.body.model].every(value => typeof value === 'string' && value.trim()) ||
              (req.body.reasoningEffort !== undefined && typeof req.body.reasoningEffort !== 'string')) return res.sendStatus(400);
          request = { sessionId, provider: req.body.provider, model: req.body.model,
            ...(req.body.reasoningEffort === undefined ? {} : { reasoningEffort: req.body.reasoningEffort }) }; break;
        case 'updateQueue': {
          if (typeof req.body.itemId !== 'string' || !req.body.itemId || !['edit', 'remove', 'steer'].includes(req.body.kind)) return res.sendStatus(400);
          if (req.body.kind === 'edit' && (typeof req.body.text !== 'string' || !req.body.text.trim())) return res.sendStatus(400);
          request = { sessionId, itemId: req.body.itemId, action: { kind: req.body.kind,
            ...(req.body.kind === 'edit' ? { content: [{ type: 'text', text: req.body.text }] } : {}) } }; break;
        }
        default: return res.sendStatus(400);
      }
      res.json(await rpc(operation, request, signal) ?? { accepted: true });
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
        handshakeTimeout: 10000, maxPayload: 0, followRedirects: false });
      const connectionId = randomUUID();
      const connection = { owner: ownerOf(req), clientId: '', pending: new Map(), send: value => send(value), cancelWait: eventId => {
        if (upstream.readyState === WebSocket.OPEN) upstream.send(JSON.stringify({ type: 'cancel', streamId: 'wait:' + eventId }));
      } };
      connections.set(connectionId, connection);
      let alive = true;
      client.on('pong', () => { alive = true; });
      const heartbeat = setInterval(() => {
        if (!alive) { client.terminate(); return; }
        alive = false; client.ping();
      }, 30000);
      heartbeat.unref();
      const send = value => {
        if (client.readyState !== WebSocket.OPEN) return;
        const text = Buffer.from(JSON.stringify(value));
        // WebSocket fragmentation bounds individual transport frames without truncating content.
        for (let offset = 0; offset < text.length; offset += 32768) {
          client.send(text.slice(offset, offset + 32768), { binary: false, fin: offset + 32768 >= text.length });
        }
      };
      const opening = setTimeout(() => { send({ type: 'error', message: '等待会话快照超时，请重新连接' }); client.close(1011); }, 15000);
      opening.unref();
      client.once('close', () => clearTimeout(opening));
      upstream.once('open', () => {
        upstream.send(JSON.stringify({ type: 'open', streamId: 'interactions', endpoint: '$events', payload: { args: {} } }));
        for (const [streamId, method, request] of [
          ['history', 'follow', { address: { kind: 'session', sessionId: id }, assistantStream: true, maxMessages: 80 }],
          ['state', 'observeState', { sessionId: id }],
          ['projections', 'observeProjections', { sessionId: id }]
        ]) upstream.send(JSON.stringify({ type: 'open', streamId, endpoint: 'session/' + method, payload: { args: { request } } }));
      });
      let questionSeq = -1;
      const questions = (value, seq) => {
        if (!Number.isSafeInteger(seq) || seq < questionSeq || client.readyState !== WebSocket.OPEN) return;
        questionSeq = seq;
        send({ type: 'questions', questions: Array.isArray(value?.active) ? value.active.filter(item => item.state === 'continued') : [] });
      };
      const endInteraction = eventId => {
        clearTimeout(connection.pending.get(eventId)?.timer);
        connection.pending.delete(eventId);
        send({ type: 'interaction-ended', eventId });
      };
      upstream.on('message', raw => {
        try {
          const frame = JSON.parse(raw.toString());
          if (frame.type === 'error') { send({ type: 'error', message: '实时会话不可用，请重新连接或切换兼容模式' }); client.close(1011); return; }
          if (frame.type === 'end' && frame.streamId?.startsWith('wait:')) {
            const eventId = frame.streamId.slice(5);
            if (connection.pending.has(eventId)) {
              endInteraction(eventId);
              rpc('$events/result', { clientId: connection.clientId, eventId, outcome: { kind: 'next' } }).catch(() => client.close(1011));
            }
            return;
          }
          if (frame.type === 'end') { client.close(1012, 'Stream ended'); return; }
          if (frame.type !== 'item') return;
          if (frame.streamId === 'projections') {
            if (frame.value?.type === 'ready') rpc('projections', { sessionId: id }).then(value => questions(value?.values?.userQuestions, value?.asOfSeq ?? -1)).catch(() => {});
            else if (frame.value?.type === 'projection' && frame.value.key === 'userQuestions') questions(frame.value.value, frame.value.seq);
          } else if (frame.streamId?.startsWith('wait:')) {
            const eventId = frame.streamId.slice(5), pending = connection.pending.get(eventId);
            const duration = frame.value?.remainingMs;
            if (!pending || !Number.isFinite(duration) || duration < 0) return;
            pending.timer = setTimeout(() => {
              if (connection.pending.get(eventId) !== pending || pending.engaged) return;
              endInteraction(eventId);
              rpc('$events/result', { clientId: connection.clientId, eventId, outcome: { kind: 'rejected',
                error: { name: 'UserQuestionError', message: 'Question wait timed out', code: 'ASK_TIMED_OUT' } } }).catch(() => client.close(1011));
            }, duration);
            pending.timer.unref();
            send({ type: 'interaction', connectionId, eventId, interaction: pending.event, request: pending.request, remainingMs: duration });
          } else if (frame.streamId === 'interactions') {
            const value = frame.value;
            if (value.type === 'ready') connection.clientId = value.clientId;
            else if (value.type === 'cancel') {
              endInteraction(value.eventId);
            } else if (value.type === 'waterfall' && connection.clientId) {
              // Delegate other sessions and unrecognised plugin interactions immediately.
              if (value.agentId !== id || !['approval/request', 'user-questions/request'].includes(value.event)) {
                rpc('$events/result', { clientId: connection.clientId, eventId: value.eventId, outcome: { kind: 'next' } }).catch(() => client.close(1011));
              } else {
                connection.pending.set(value.eventId, value);
                if (value.request?.wait?.timed === true) {
                  upstream.send(JSON.stringify({ type: 'open', streamId: 'wait:' + value.eventId, endpoint: 'userQuestions/attachWait',
                    payload: { args: { agent: id, callId: value.request.wait.callId } } }));
                } else send({ type: 'interaction', connectionId, eventId: value.eventId, interaction: value.event, request: value.request });
              }
            }
          } else if (frame.streamId === 'state') send({ type: 'state', running: frame.value?.running === true,
            waiting: Array.isArray(frame.value?.pendingInput) && frame.value.pendingInput.length > 0 });
          else if (frame.streamId === 'history') {
            if (frame.value?.type === 'snapshot') clearTimeout(opening);
            const value = normalizeFollow(frame.value); if (value) send(value); }
        } catch { client.close(1011, 'Invalid stream'); }
      });
      client.on('message', () => client.close(1008, 'Read-only channel'));
      client.once('close', () => { clearInterval(heartbeat); connections.delete(connectionId); for (const pending of connection.pending.values()) clearTimeout(pending.timer); upstream.terminate(); });
      client.on('error', () => upstream.terminate());
      upstream.on('error', () => { send({ type: 'error', message: '实时连接失败，请检查连接或切换兼容模式' }); client.close(1011); });
      upstream.once('close', () => { if (client.readyState === WebSocket.OPEN) client.close(1012); });
    });
  }
  return { routes, upgrade, close() { for (const client of wss.clients) client.terminate(); wss.close(); } };
}
