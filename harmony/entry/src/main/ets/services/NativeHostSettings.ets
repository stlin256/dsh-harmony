/** Redacted Host profile mirror. Local notification/connection settings do not enter this document. */
export class NativeSettingsNamespace {
  ns: string = '';
  value: Record<string, Object> = {};
  revision: number = 0;
}
export class NativeSettingsDescription {
  writable: boolean = false;
  namespaces: NativeSettingsNamespace[] = [];
}
export class NativeChatPreferences {
  mode: string = 'detailed';
  collapseTiming: string = 'completion';
  foldedReplies: string = 'all';
  busyEnter: string = 'queue';
}
export function nativeChatPreferences(rows: NativeSettingsNamespace[]): NativeChatPreferences {
  const value = new NativeChatPreferences();
  const chat = rows.find((row: NativeSettingsNamespace) => row.ns === 'ui-chat')?.value || {};
  const input = rows.find((row: NativeSettingsNamespace) => row.ns === 'ui-conversation')?.value || {};
  if (typeof chat.transcriptView === 'string' && ['compact','standard','detailed','verbose'].includes(chat.transcriptView)) value.mode = chat.transcriptView;
  if (chat.collapseTiming === 'next-input') value.collapseTiming = 'next-input';
  if (chat.foldedReplies === 'final') value.foldedReplies = 'final';
  if (input.busyEnter === 'steer') value.busyEnter = 'steer';
  return value;
}
export class NativeHostSettings {
  description: NativeSettingsDescription = new NativeSettingsDescription();
  loaded: boolean = false;
  private reads: number = 0;
  private refreshing: Promise<void> | null = null;
  private refreshAgain: boolean = false;
  private writes: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private call: (value: string) => Promise<string>;
  private changed: () => void;
  constructor(call: (value: string) => Promise<string>, changed: () => void = (): void => {}) { this.call = call; this.changed = changed; }
  chat(): NativeChatPreferences { return nativeChatPreferences(this.description.namespaces); }
  refresh(force: boolean = false): Promise<void> {
    if (this.refreshing) { if (force) this.refreshAgain = true; return this.refreshing; }
    const pending = this.read().finally((): void => { this.refreshing = null; });
    this.refreshing = pending;
    return pending;
  }
  private async read(): Promise<void> {
    do {
      this.refreshAgain = false;
      const version = ++this.reads;
      const value = JSON.parse(await this.call(JSON.stringify({ operation: 'settingsDescribe' }))) as NativeSettingsDescription;
      if (version === this.reads) { this.description = value; this.loaded = true; this.changed(); }
    } while (this.refreshAgain);
  }
  set(ns: string, field: string, value: string | number): Promise<void> {
    const previous = this.writes.get(ns) || Promise.resolve();
    const pending = previous.catch(() => {}).then(async (): Promise<void> => {
      if (!this.loaded) await this.refresh();
      const row = this.description.namespaces.find((item: NativeSettingsNamespace) => item.ns === ns);
      if (!this.description.writable || !row) throw new Error('Settings unavailable');
      try {
        const result = JSON.parse(await this.call(JSON.stringify({ operation: 'settingsSet', ns, field, value, revision: row.revision }))) as NativeSettingsNamespace;
        this.reads++;
        const next = new NativeSettingsDescription(); next.writable = this.description.writable;
        next.namespaces = this.description.namespaces.map((item: NativeSettingsNamespace) => item.ns === ns ? result : item);
        this.description = next;
        this.changed();
      } catch (error) {
        try { await this.refresh(true); } catch (_) {}
        throw error as Error;
      }
    });
    this.writes.set(ns, pending);
    return pending;
  }
}
