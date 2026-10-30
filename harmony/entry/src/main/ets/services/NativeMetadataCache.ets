import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { NativeSession, NativeSessionList, NativeWorkspaceItem, NativeWorkspaceSnapshot } from './NativeSessionModel';

class NativeCacheEntry {
  savedAt: number = 0;
  sessions: NativeSession[] = [];
  workspaces: NativeWorkspaceSnapshot | null = null;
}

/**
 * Non-sensitive navigation metadata survives a process restart. Message bodies
 * and credentials remain in memory/WebKit storage and are never written here.
 */
export class NativeMetadataCache {
  private static memory: Map<string, NativeCacheEntry> = new Map<string, NativeCacheEntry>();
  private static key(origin: string): string {
    let hash = 2166136261;
    for (let index = 0; index < origin.length; index++) {
      hash ^= origin.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return 'metadata:' + (hash >>> 0).toString(16);
  }
  private static routeKey(origin: string): string {
    return NativeMetadataCache.key(origin) + ':last-session';
  }
  private static store(context: common.UIAbilityContext): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: 'dsh-native-navigation-cache' });
  }
  static read(context: common.UIAbilityContext, origin: string): NativeCacheEntry {
    const id = NativeMetadataCache.key(origin);
    const cached = NativeMetadataCache.memory.get(id);
    if (cached) return cached;
    const empty = new NativeCacheEntry();
    try {
      const raw = NativeMetadataCache.store(context).getSync(id, '') as string;
      if (!raw) return empty;
      const value = JSON.parse(raw) as NativeCacheEntry;
      if (!Array.isArray(value.sessions) || value.savedAt <= 0) return empty;
      NativeMetadataCache.memory.set(id, value);
      return value;
    } catch (_) { return empty; }
  }
  static save(context: common.UIAbilityContext, origin: string, sessions: NativeSession[],
    workspaces: NativeWorkspaceSnapshot | null): void {
    const id = NativeMetadataCache.key(origin);
    const value = new NativeCacheEntry();
    value.savedAt = Date.now();
    value.sessions = sessions.slice(0, 200);
    if (workspaces && workspaces.available) {
      const snapshot = new NativeWorkspaceSnapshot();
      snapshot.available = workspaces.available;
      snapshot.archivedSessionIds = workspaces.archivedSessionIds.slice();
      snapshot.pinnedSessionIds = workspaces.pinnedSessionIds.slice();
      snapshot.items = workspaces.items.slice(0, 100).map((item: NativeWorkspaceItem): NativeWorkspaceItem => {
        const row = new NativeWorkspaceItem();
        row.workspaceId = item.workspaceId; row.path = item.path; row.title = item.title;
        row.sessionIds = item.sessionIds.slice(0, 500);
        return row;
      });
      value.workspaces = snapshot;
    }
    NativeMetadataCache.memory.set(id, value);
    try {
      const store = NativeMetadataCache.store(context);
      store.putSync(id, JSON.stringify(value));
      store.flush().catch(() => {});
    } catch (_) {}
  }
  static readLastSession(context: common.UIAbilityContext, origin: string): string {
    try {
      const value = NativeMetadataCache.store(context).getSync(NativeMetadataCache.routeKey(origin), '') as string;
      return /^[A-Za-z0-9_-]{1,160}$/.test(value) ? value : '';
    } catch (_) { return ''; }
  }
  static rememberSession(context: common.UIAbilityContext, origin: string, sessionId: string): void {
    if (!/^[A-Za-z0-9_-]{1,160}$/.test(sessionId)) return;
    try {
      const store = NativeMetadataCache.store(context);
      store.putSync(NativeMetadataCache.routeKey(origin), sessionId);
      store.flush().catch(() => {});
    } catch (_) {}
  }
  static forgetSession(context: common.UIAbilityContext, origin: string): void {
    try {
      const store = NativeMetadataCache.store(context);
      store.deleteSync(NativeMetadataCache.routeKey(origin));
      store.flush().catch(() => {});
    } catch (_) {}
  }
  static clear(context: common.UIAbilityContext, origin: string): void {
    const id = NativeMetadataCache.key(origin);
    const route = NativeMetadataCache.routeKey(origin);
    NativeMetadataCache.memory.delete(id);
    try {
      const store = NativeMetadataCache.store(context);
      store.deleteSync(id);
      store.deleteSync(route);
      store.flush().catch(() => {});
    } catch (_) {}
  }
}
