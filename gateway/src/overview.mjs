const states = { 'run.started': 'running', 'run.completed': 'completed', 'run.failed': 'failed', 'run.stopped': 'stopped' };
export const eventCodes = [...Object.keys(states), 'permission.required', 'permission.resolved'];
export const notificationCodes = ['run.completed', 'run.failed', 'permission.required'];

/** Called in the event transaction. Old plugin payloads still notify, but cannot
 * mutate the projection without a monotonic Harness session sequence. */
export function projectEvent(db, event, now) {
  if (event.seq === undefined) return true;
  const previous = db.prepare('SELECT seq,state FROM task_states WHERE session = ?').get(event.sessionId);
  if (previous && event.seq <= previous.seq) return false;
  const state = states[event.code] || previous?.state || 'running';
  db.prepare(`INSERT INTO task_states VALUES (?,?,?,?) ON CONFLICT(session)
    DO UPDATE SET seq=excluded.seq,state=excluded.state,updated=excluded.updated`).run(event.sessionId, event.seq, state, now);
  if (event.code === 'permission.required') {
    db.prepare('INSERT OR IGNORE INTO pending_actions VALUES (?,?)').run(event.sessionId, event.approvalId);
  } else if (event.code === 'permission.resolved') {
    db.prepare('DELETE FROM pending_actions WHERE session = ? AND approval = ?').run(event.sessionId, event.approvalId);
  } else {
    db.prepare('DELETE FROM pending_actions WHERE session = ?').run(event.sessionId);
  }
  if (event.code !== 'permission.required' && !db.prepare('SELECT 1 FROM pending_actions WHERE session = ? LIMIT 1').get(event.sessionId)) {
    // A delayed approval reminder must not survive resolution or turn end.
    db.prepare("DELETE FROM jobs WHERE json_extract(payload, '$.sessionId') = ? AND json_extract(payload, '$.code') = 'permission.required'").run(event.sessionId);
  }
  return true;
}

/** Aggregate only: no session IDs, hostnames, message text or credentials. */
export function readOverview(db, now = Date.now()) {
  const result = { running: 0, waiting: 0, completed: 0, failed: 0, unknown: 0, observedAt: 0, generatedAt: now };
  for (const row of db.prepare(`SELECT state,updated,EXISTS(SELECT 1 FROM pending_actions p WHERE p.session=t.session) AS pending FROM task_states t`).all()) {
    result.observedAt = Math.max(result.observedAt, row.updated);
    if (row.state === 'running') {
      if (now - row.updated > 6 * 3600000) result.unknown++;
      else if (row.pending) result.waiting++;
      else result.running++;
    } else if (now - row.updated <= 86400000 && (row.state === 'completed' || row.state === 'failed')) result[row.state]++;
  }
  return result;
}
