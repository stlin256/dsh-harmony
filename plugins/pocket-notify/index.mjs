/** DeepSeek Harness Cordis plugin. No conversation content leaves the host. */
export const name = 'dsh-pocket-notify';
export function routingEvent(session, event) {
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(session.id)) return null;
  let code;
  if (event.type === 'turn/end') {
    if (event.data.reason.kind === 'completed') code = 'run.completed';
    else if (event.data.reason.kind === 'error') code = 'run.failed';
    else return null; // User cancellation is not a task completion.
  } else if (event.type === 'approval/asked') code = 'permission.required';
  else return null;
  return { id: `${session.id}:${event.seq}:${code}`, sessionId: session.id, code };
}

export function apply(ctx, config = {}) {
  const endpoint = config.endpoint || process.env.POCKET_EVENT_ENDPOINT;
  const secret = process.env.POCKET_EVENT_SECRET;
  if (!endpoint || !secret || secret.length < 32) throw Error('Pocket notifier needs endpoint and POCKET_EVENT_SECRET');
  const url = new URL(endpoint);
  if (url.protocol !== 'https:') throw Error('Pocket notifier requires HTTPS');
  let disposed = false;
  const queue = new Map();
  const active = new Set();
  let draining = false;
  const drain = async () => {
    if (disposed || draining) return;
    draining = true;
    try {
      for (const [id, item] of queue) {
        if (disposed) break;
        if (item.expires <= Date.now()) { queue.delete(id); continue; }
        if (item.due > Date.now()) continue;
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 10000);
        active.add(controller);
        try {
          const response = await fetch(url, { method: 'POST', redirect: 'error', signal: controller.signal,
            headers: { Authorization: 'Bearer ' + secret, 'Content-Type': 'application/json' }, body: JSON.stringify(item.event) });
          if (!response.ok) throw Error('Event rejected');
          await response.body?.cancel();
          queue.delete(id);
        } catch {
          item.attempts++;
          item.due = Date.now() + Math.min(60000, 1000 * 2 ** item.attempts);
        } finally { clearTimeout(timeout); active.delete(controller); }
      }
    } finally { draining = false; }
  };
  ctx.on('session/event', (session, event) => {
    if (typeof session.inheritedEventCount === 'number' && event.seq < session.inheritedEventCount) return;
    const value = routingEvent(session, event);
    if (!value || disposed || queue.has(value.id)) return;
    if (queue.size >= 1000) { ctx.logger?.warn('Pocket notification queue full'); return; }
    queue.set(value.id, { event: value, due: Date.now(), expires: Date.now() + 3600000, attempts: 0 });
    // Never wait for the notification service on the agent event path.
    void drain();
  }, { global: true });
  const timer = setInterval(() => { void drain(); }, 1000);
  timer.unref();
  ctx.on('dispose', () => {
    disposed = true; clearInterval(timer);
    for (const controller of active) controller.abort();
    queue.clear();
  });
}
