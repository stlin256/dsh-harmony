import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, chmodSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomBytes, createHash } from 'node:crypto';

export const digest = value => createHash('sha256').update(value).digest('hex');
export const random = () => randomBytes(32).toString('base64url');

export class Store {
  constructor(config) {
    this.config = config;
    mkdirSync(dirname(config.database), { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(config.database);
    chmodSync(config.database, 0o600);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY, subject TEXT NOT NULL, created INTEGER NOT NULL,
        seen INTEGER NOT NULL, expires INTEGER NOT NULL, device TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS flows (
        id TEXT PRIMARY KEY, binding TEXT NOT NULL, verifier TEXT NOT NULL,
        nonce TEXT NOT NULL, expires INTEGER NOT NULL
      );`);
  }
  newFlow(state, binding, verifier, nonce) {
    this.db.prepare('INSERT INTO flows VALUES(?,?,?,?,?)')
      .run(digest(state), digest(binding), verifier, nonce, Date.now() + 600_000);
  }
  takeFlow(state, binding) {
    if (!state || !binding || state.length > 256 || binding.length > 256) return null;
    const row = this.db.prepare('DELETE FROM flows WHERE id=? AND binding=? RETURNING *')
      .get(digest(state), digest(binding));
    return row?.expires > Date.now() ? row : null;
  }
  create(subject, device) {
    const token = random(), now = Date.now();
    this.db.prepare('INSERT INTO sessions VALUES(?,?,?,?,?,?)')
      .run(digest(token), subject, now, now, now + this.config.maxAge, device);
    return token;
  }
  session(token, touch = false) {
    if (!token || !/^[A-Za-z0-9_-]{43}$/.test(token)) return null;
    return this.byId(digest(token), touch);
  }
  byId(id, touch = false) {
    const row = this.db.prepare('SELECT * FROM sessions WHERE id=?').get(id);
    const now = Date.now();
    if (!row) return null;
    if (now < row.created || row.expires <= now || row.seen + this.config.idleAge <= now
        || !this.config.subjects.has(row.subject)) {
      this.revoke(id); return null;
    }
    if (touch && now - row.seen > 30_000) {
      this.db.prepare('UPDATE sessions SET seen=? WHERE id=?').run(now, id);
      row.seen = now;
    }
    return row;
  }
  revoke(id) { this.db.prepare('DELETE FROM sessions WHERE id=?').run(id); }
  list() { return this.db.prepare('SELECT * FROM sessions ORDER BY created DESC').all(); }
  prune() {
    const now = Date.now();
    this.db.prepare('DELETE FROM flows WHERE expires<=?').run(now);
    this.db.prepare('DELETE FROM sessions WHERE expires<=? OR seen<=?')
      .run(now, now - this.config.idleAge);
  }
  close() { this.db.close(); }
}
