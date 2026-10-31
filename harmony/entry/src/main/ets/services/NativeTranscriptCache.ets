import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import {
  NativeSessionCacheRecord,
  NativeSessionModel
} from './NativeSessionModel';

const TRANSCRIPT_CHUNK_CHARS: number = 256 * 1024;

/** SQLite substr/length use Unicode code points rather than UTF-16 units. */
export function nativeCodePointLength(value: string): number {
  let count = 0;
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
      const next = value.charCodeAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) index++;
    }
    count++;
  }
  return count;
}

/**
 * RDB shared blocks can reject multi-megabyte TEXT reads. Split captured JSON
 * before persistence and never cut a UTF-16 surrogate pair.
 */
export function nativeTranscriptChunks(payload: string, limit: number = TRANSCRIPT_CHUNK_CHARS): string[] {
  const chunks: string[] = [];
  const safeLimit = Math.max(1024, limit);
  let start = 0;
  while (start < payload.length) {
    let end = Math.min(payload.length, start + safeLimit);
    if (end < payload.length) {
      const code = payload.charCodeAt(end - 1);
      if (code >= 0xD800 && code <= 0xDBFF) end--;
    }
    if (end <= start) end = Math.min(payload.length, start + safeLimit);
    chunks.push(payload.slice(start, end));
    start = end;
  }
  return chunks;
}

/** Content is scoped by the one-way gateway/login cache key and stored in an encrypted RDB. */
export class NativeTranscriptCache {
  private static store: relationalStore.RdbStore | null = null;
  private static opening: Promise<relationalStore.RdbStore> | null = null;
  private static writes: Promise<void> = Promise.resolve();
  private static scopeId(value: string): string {
    let first = 2166136261;
    let second = 5381;
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      first = Math.imul(first ^ code, 16777619);
      second = Math.imul(second, 33) ^ code;
    }
    return (first >>> 0).toString(16) + ':' + (second >>> 0).toString(16) + ':' + value.length.toString(16);
  }

  private static async database(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    if (NativeTranscriptCache.store) return NativeTranscriptCache.store;
    if (NativeTranscriptCache.opening) return NativeTranscriptCache.opening;
    const opening = relationalStore.getRdbStore(context, {
      name: 'dsh-harmony-transcripts.db',
      securityLevel: relationalStore.SecurityLevel.S3,
      encrypt: true
    }).then(async (store: relationalStore.RdbStore): Promise<relationalStore.RdbStore> => {
      await store.executeSql(`CREATE TABLE IF NOT EXISTS transcript_cache(
        scope_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        bytes INTEGER NOT NULL,
        PRIMARY KEY(scope_id, session_id)
      )`);
      await store.executeSql('CREATE INDEX IF NOT EXISTS transcript_cache_access ON transcript_cache(updated_at)');
      await store.executeSql(`CREATE TABLE IF NOT EXISTS transcript_manifest(
        scope_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        chunk_count INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        bytes INTEGER NOT NULL,
        PRIMARY KEY(scope_id, session_id)
      )`);
      await store.executeSql(
        'CREATE INDEX IF NOT EXISTS transcript_manifest_access ON transcript_manifest(updated_at)');
      await store.executeSql(`CREATE TABLE IF NOT EXISTS transcript_chunk(
        scope_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY(scope_id, session_id, chunk_index)
      )`);
      await store.executeSql(`CREATE TABLE IF NOT EXISTS route_state(
        scope_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )`);
      NativeTranscriptCache.store = store;
      return store;
    }).finally((): void => { NativeTranscriptCache.opening = null; });
    NativeTranscriptCache.opening = opening;
    return opening;
  }

  static saveSession(context: common.UIAbilityContext, scope: string, sessionId: string,
    model: NativeSessionModel): Promise<void> {
    const scopeId = NativeTranscriptCache.scopeId(scope);
    // Capture synchronously so a queued write persists this exact model state
    // rather than a later streaming mutation of the same model object.
    const payload = JSON.stringify(model.capture());
    const chunks = nativeTranscriptChunks(payload);
    const operation = NativeTranscriptCache.writes.catch((): void => {}).then(async (): Promise<void> => {
      const store = await NativeTranscriptCache.database(context);
      const now = Date.now();
      store.beginTransaction();
      try {
        await store.executeSql(
          'DELETE FROM transcript_chunk WHERE scope_id=? AND session_id=?', [scopeId, sessionId]);
        await store.executeSql(
          'DELETE FROM transcript_cache WHERE scope_id=? AND session_id=?', [scopeId, sessionId]);
        for (let index = 0; index < chunks.length; index++) {
          await store.executeSql(
            'INSERT INTO transcript_chunk(scope_id,session_id,chunk_index,payload) VALUES (?,?,?,?)',
            [scopeId, sessionId, index, chunks[index]]);
        }
        await store.executeSql(`INSERT INTO transcript_manifest(
          scope_id,session_id,chunk_count,updated_at,bytes) VALUES (?,?,?,?,?)
          ON CONFLICT(scope_id,session_id) DO UPDATE SET
          chunk_count=excluded.chunk_count,updated_at=excluded.updated_at,bytes=excluded.bytes`,
          [scopeId, sessionId, chunks.length, now, payload.length]);
        store.commit();
      } catch (error) {
        store.rollBack();
        throw error as Error;
      }
    });
    NativeTranscriptCache.writes = operation;
    return operation;
  }

  private static async readLegacyPayload(store: relationalStore.RdbStore,
    scopeId: string, sessionId: string): Promise<string> {
    const size = await store.querySql(
      'SELECT length(payload) FROM transcript_cache WHERE scope_id=? AND session_id=? LIMIT 1',
      [scopeId, sessionId]);
    let total = 0;
    try {
      if (!size.goToFirstRow()) return '';
      total = size.getLong(0);
    } finally {
      size.close();
    }
    if (total <= 0) return '';
    let payload = '';
    let offset = 1;
    let consumed = 0;
    while (consumed < total) {
      const length = Math.min(TRANSCRIPT_CHUNK_CHARS, total - consumed);
      const part = await store.querySql(
        'SELECT substr(payload,?,?) FROM transcript_cache WHERE scope_id=? AND session_id=? LIMIT 1',
        [offset, length, scopeId, sessionId]);
      try {
        if (!part.goToFirstRow()) return '';
        const value = part.getString(0);
        if (!value) return '';
        payload += value;
        const points = nativeCodePointLength(value);
        offset += points;
        consumed += points;
      } finally {
        part.close();
      }
    }
    return consumed === total ? payload : '';
  }

  static async loadSession(context: common.UIAbilityContext, scope: string,
    sessionId: string): Promise<NativeSessionCacheRecord | null> {
    const scopeId = NativeTranscriptCache.scopeId(scope);
    try {
      await NativeTranscriptCache.writes;
      const store = await NativeTranscriptCache.database(context);
      const manifest = await store.querySql(
        'SELECT chunk_count,bytes FROM transcript_manifest WHERE scope_id=? AND session_id=? LIMIT 1',
        [scopeId, sessionId]);
      let chunkCount = -1;
      let expectedBytes = -1;
      try {
        if (manifest.goToFirstRow()) {
          chunkCount = manifest.getLong(0);
          expectedBytes = manifest.getLong(1);
        }
      } finally {
        manifest.close();
      }
      if (chunkCount >= 0) {
        if (chunkCount === 0 || expectedBytes <= 0) return null;
        const parts: string[] = [];
        const chunks = await store.querySql(
          'SELECT chunk_index,payload FROM transcript_chunk WHERE scope_id=? AND session_id=? ORDER BY chunk_index ASC',
          [scopeId, sessionId]);
        try {
          let row = chunks.goToFirstRow();
          let expectedIndex = 0;
          while (row) {
            if (chunks.getLong(0) !== expectedIndex) return null;
            parts.push(chunks.getString(1));
            expectedIndex++;
            row = chunks.goToNextRow();
          }
        } finally {
          chunks.close();
        }
        if (parts.length !== chunkCount) return null;
        const payload = parts.join('');
        if (payload.length !== expectedBytes) return null;
        const saved = JSON.parse(payload) as NativeSessionCacheRecord;
        await store.executeSql(
          'UPDATE transcript_manifest SET updated_at=? WHERE scope_id=? AND session_id=?',
          [Date.now(), scopeId, sessionId]);
        return saved;
      }

      // Compatibility path for caches created before transcript chunking.
      const payload = await NativeTranscriptCache.readLegacyPayload(store, scopeId, sessionId);
      if (!payload) return null;
      const saved = JSON.parse(payload) as NativeSessionCacheRecord;
      await store.executeSql(
        'UPDATE transcript_cache SET updated_at=? WHERE scope_id=? AND session_id=?',
        [Date.now(), scopeId, sessionId]);
      // Return the first paint immediately; migration then replaces the large
      // legacy row with bounded chunks for all later launches.
      const restored = new NativeSessionModel();
      restored.restore(saved);
      NativeTranscriptCache.saveSession(context, scope, sessionId, restored).catch((): void => {});
      return saved;
    } catch (_) {
      // A transient query or shared-block error must not destroy the only
      // available cache. Keep it for a later retry.
      return null;
    }
  }

  static clearSession(context: common.UIAbilityContext, scope: string, sessionId: string): Promise<void> {
    const scopeId = NativeTranscriptCache.scopeId(scope);
    const operation = NativeTranscriptCache.writes.catch((): void => {}).then(async (): Promise<void> => {
      const store = await NativeTranscriptCache.database(context);
      store.beginTransaction();
      try {
        await store.executeSql('DELETE FROM transcript_chunk WHERE scope_id=? AND session_id=?', [scopeId, sessionId]);
        await store.executeSql('DELETE FROM transcript_manifest WHERE scope_id=? AND session_id=?', [scopeId, sessionId]);
        await store.executeSql('DELETE FROM transcript_cache WHERE scope_id=? AND session_id=?', [scopeId, sessionId]);
        await store.executeSql('DELETE FROM route_state WHERE scope_id=? AND session_id=?', [scopeId, sessionId]);
        store.commit();
      } catch (error) {
        store.rollBack();
        throw error as Error;
      }
    });
    NativeTranscriptCache.writes = operation;
    return operation;
  }

  static clearScope(context: common.UIAbilityContext, scope: string): Promise<void> {
    const scopeId = NativeTranscriptCache.scopeId(scope);
    const operation = NativeTranscriptCache.writes.catch((): void => {}).then(async (): Promise<void> => {
      const store = await NativeTranscriptCache.database(context);
      store.beginTransaction();
      try {
        await store.executeSql('DELETE FROM transcript_chunk WHERE scope_id=?', [scopeId]);
        await store.executeSql('DELETE FROM transcript_manifest WHERE scope_id=?', [scopeId]);
        await store.executeSql('DELETE FROM transcript_cache WHERE scope_id=?', [scopeId]);
        await store.executeSql('DELETE FROM route_state WHERE scope_id=?', [scopeId]);
        store.commit();
      } catch (error) {
        store.rollBack();
        throw error as Error;
      }
    });
    NativeTranscriptCache.writes = operation;
    return operation;
  }

  static async saveRoute(context: common.UIAbilityContext, scope: string, sessionId: string): Promise<void> {
    const scopeId = NativeTranscriptCache.scopeId(scope);
    const operation = NativeTranscriptCache.writes.catch((): void => {}).then(async (): Promise<void> => {
      const store = await NativeTranscriptCache.database(context);
      await store.executeSql(`INSERT INTO route_state(scope_id,session_id,updated_at) VALUES (?,?,?)
        ON CONFLICT(scope_id) DO UPDATE SET session_id=excluded.session_id,updated_at=excluded.updated_at`,
        [scopeId, sessionId, Date.now()]);
    });
    NativeTranscriptCache.writes = operation;
    return operation;
  }

  static async loadRoute(context: common.UIAbilityContext, scope: string): Promise<string> {
    await NativeTranscriptCache.writes;
    const store = await NativeTranscriptCache.database(context);
    const result = await store.querySql('SELECT session_id FROM route_state WHERE scope_id=? LIMIT 1',
      [NativeTranscriptCache.scopeId(scope)]);
    try {
      if (!result.goToFirstRow()) return '';
      const id = result.getString(0);
      return /^[A-Za-z0-9_-]{1,160}$/.test(id) ? id : '';
    } finally {
      result.close();
    }
  }

  static async forgetSession(context: common.UIAbilityContext, scope: string, sessionId: string): Promise<void> {
    await NativeTranscriptCache.clearSession(context, scope, sessionId);
  }

  static trimToQuota(context: common.UIAbilityContext, scope: string,
    activeSessionId: string, protectedSessionIds: string[] = [],
    quota: number = 512 * 1024 * 1024): Promise<void> {
    const scopeId = NativeTranscriptCache.scopeId(scope);
    const protectedIds: Set<string> = new Set<string>(protectedSessionIds);
    const operation = NativeTranscriptCache.writes.catch((): void => {}).then(async (): Promise<void> => {
      const store = await NativeTranscriptCache.database(context);
      const chunkTotal = await store.querySql('SELECT COALESCE(SUM(bytes),0) FROM transcript_manifest');
      const legacyTotal = await store.querySql('SELECT COALESCE(SUM(bytes),0) FROM transcript_cache');
      let bytes = 0;
      try {
        if (chunkTotal.goToFirstRow()) bytes += chunkTotal.getLong(0);
        if (legacyTotal.goToFirstRow()) bytes += legacyTotal.getLong(0);
      } finally {
        chunkTotal.close();
        legacyTotal.close();
      }
      while (bytes > quota) {
        const rows = await store.querySql(
          `SELECT scope_id,session_id,bytes,updated_at FROM transcript_manifest
           WHERE NOT(scope_id=? AND session_id=?)
           UNION ALL
           SELECT scope_id,session_id,bytes,updated_at FROM transcript_cache
           WHERE NOT(scope_id=? AND session_id=?)
           ORDER BY updated_at ASC LIMIT 64`,
          [scopeId, activeSessionId, scopeId, activeSessionId]);
        const staleScope: string[] = [];
        const staleSessions: string[] = [];
        let removedBytes: number = 0;
        try {
          while (rows.goToNextRow()) {
            const savedScope = rows.getString(0);
            const sessionId = rows.getString(1);
            if (savedScope === scopeId && protectedIds.has(sessionId)) continue;
            staleScope.push(savedScope);
            staleSessions.push(sessionId);
            removedBytes += rows.getLong(2);
          }
        } finally {
          rows.close();
        }
        if (!staleScope.length) break;
        for (let index = 0; index < staleScope.length; index++) {
          await store.executeSql('DELETE FROM transcript_chunk WHERE scope_id=? AND session_id=?',
            [staleScope[index], staleSessions[index]]);
          await store.executeSql('DELETE FROM transcript_manifest WHERE scope_id=? AND session_id=?',
            [staleScope[index], staleSessions[index]]);
          await store.executeSql('DELETE FROM transcript_cache WHERE scope_id=? AND session_id=?',
            [staleScope[index], staleSessions[index]]);
        }
        bytes -= removedBytes;
      }
    });
    NativeTranscriptCache.writes = operation;
    return operation;
  }
}
