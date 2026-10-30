import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import {
  NativeSessionCacheRecord,
  NativeSessionModel
} from './NativeSessionModel';

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
    const operation = NativeTranscriptCache.writes.catch((): void => {}).then(async (): Promise<void> => {
      const store = await NativeTranscriptCache.database(context);
      await store.executeSql(`INSERT INTO transcript_cache(scope_id,session_id,payload,updated_at,bytes)
        VALUES (?,?,?,?,?) ON CONFLICT(scope_id,session_id)
        DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at,bytes=excluded.bytes`,
        [scopeId, sessionId, payload, Date.now(), payload.length]);
    });
    NativeTranscriptCache.writes = operation;
    return operation;
  }

  static async loadSession(context: common.UIAbilityContext, scope: string,
    sessionId: string): Promise<NativeSessionCacheRecord | null> {
    const scopeId = NativeTranscriptCache.scopeId(scope);
    try {
      await NativeTranscriptCache.writes;
      const store = await NativeTranscriptCache.database(context);
      const result = await store.querySql(
        'SELECT payload FROM transcript_cache WHERE scope_id=? AND session_id=? LIMIT 1',
        [scopeId, sessionId]);
      try {
        if (!result.goToFirstRow()) return null;
        const saved = JSON.parse(result.getString(0)) as NativeSessionCacheRecord;
        await store.executeSql(
          'UPDATE transcript_cache SET updated_at=? WHERE scope_id=? AND session_id=?',
          [Date.now(), scopeId, sessionId]);
        return saved;
      } finally {
        result.close();
      }
    } catch (_) {
      await NativeTranscriptCache.clearSession(context, scope, sessionId).catch((): void => {});
      return null;
    }
  }

  static clearSession(context: common.UIAbilityContext, scope: string, sessionId: string): Promise<void> {
    const scopeId = NativeTranscriptCache.scopeId(scope);
    const operation = NativeTranscriptCache.writes.catch((): void => {}).then(async (): Promise<void> => {
      const store = await NativeTranscriptCache.database(context);
      store.beginTransaction();
      try {
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
      const total = await store.querySql('SELECT COALESCE(SUM(bytes),0) FROM transcript_cache');
      let bytes = 0;
      try {
        if (total.goToFirstRow()) bytes = total.getLong(0);
      } finally {
        total.close();
      }
      while (bytes > quota) {
        const rows = await store.querySql(
          'SELECT scope_id,session_id,bytes FROM transcript_cache WHERE NOT(scope_id=? AND session_id=?) ORDER BY updated_at ASC LIMIT 64',
          [scopeId, activeSessionId]);
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
