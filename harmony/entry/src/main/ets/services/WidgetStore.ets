import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';

export class WidgetData {
  headline: string = '连接工作空间';
  detail: string = '打开应用，连接你的 Harness';
  stamp: string = '尚未同步';
  showCounts: boolean = false;
  running: string = '—';
  waiting: string = '—';
  completed: string = '—';
  failed: string = '—';
}

export class OverviewSnapshot {
  running: number = 0;
  waiting: number = 0;
  completed: number = 0;
  failed: number = 0;
  unknown: number = 0;
  observedAt: number = 0;
  generatedAt: number = 0;
}

/** Separate single-writer files: UI writes snapshots; extension writes instance
 * IDs. Refresh Preferences' process-local cache before every cross-process read. */
export class WidgetStore {
  private static pending: Promise<void> = Promise.resolve();

  private static enqueue(task: () => Promise<void>): Promise<void> {
    const next = WidgetStore.pending.then(task);
    WidgetStore.pending = next.catch(() => {});
    return next;
  }
  private static fresh(context: common.Context, name: string): preferences.Preferences {
    const app = context.getApplicationContext();
    preferences.removePreferencesFromCacheSync(app, { name: name });
    return preferences.getPreferencesSync(app, { name: name });
  }

  static register(context: common.Context, id: string): void {
    if (!/^[0-9]{1,32}$/.test(id)) return;
    const store = WidgetStore.fresh(context, 'pocket-widget-instances');
    const ids = store.getSync('ids', []) as string[];
    if (!ids.includes(id)) { ids.push(id); store.putSync('ids', ids); store.flushSync(); }
  }

  static remove(context: common.Context, id: string): void {
    const store = WidgetStore.fresh(context, 'pocket-widget-instances');
    const ids = (store.getSync('ids', []) as string[]).filter((item: string) => item !== id);
    store.putSync('ids', ids);
    store.flushSync();
  }

  static detailsEnabled(context: common.Context): boolean {
    return WidgetStore.fresh(context, 'pocket-widget-snapshot').getSync('details', false) === true;
  }

  static async setDetails(context: common.Context, enabled: boolean): Promise<void> {
    await WidgetStore.enqueue(async (): Promise<void> => {
      const store = WidgetStore.fresh(context, 'pocket-widget-snapshot');
      store.putSync('details', enabled);
      // Clear prior aggregate values when the user switches privacy mode.
      store.putSync('snapshot', '');
      store.putSync('syncedAt', 0);
      store.flushSync();
      await WidgetStore.publish(context);
    });
  }

  static async update(context: common.Context, snapshot: OverviewSnapshot): Promise<void> {
    await WidgetStore.enqueue(async (): Promise<void> => {
      const store = WidgetStore.fresh(context, 'pocket-widget-snapshot');
      store.putSync('connected', true);
      store.putSync('syncedAt', Date.now());
      store.putSync('snapshot', store.getSync('details', false) === true ? JSON.stringify(snapshot) : '');
      store.flushSync();
      await WidgetStore.publish(context);
    });
  }

  static async clear(context: common.Context): Promise<void> {
    await WidgetStore.enqueue(async (): Promise<void> => {
      const store = WidgetStore.fresh(context, 'pocket-widget-snapshot');
      store.putSync('connected', false);
      store.putSync('details', false);
      store.putSync('syncedAt', 0);
      store.putSync('snapshot', '');
      store.flushSync();
      await WidgetStore.publish(context);
    });
  }

  static data(context: common.Context): WidgetData {
    const data = new WidgetData();
    const store = WidgetStore.fresh(context, 'pocket-widget-snapshot');
    if (store.getSync('connected', false) !== true) return data;
    data.headline = '继续你的工作';
    data.detail = '打开 Harness 工作空间';
    const time = store.getSync('syncedAt', 0) as number;
    if (time <= 0) { data.stamp = '打开应用同步'; return data; }
    const date = new Date(time);
    data.stamp = '快照 ' + (date.getMonth() + 1) + '/' + date.getDate() + ' ' +
      date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
    if (Date.now() < time || Date.now() - time > 15 * 60000) { data.detail = '快照已过期，打开应用更新'; return data; }
    if (store.getSync('details', false) !== true) return data;
    const raw = store.getSync('snapshot', '') as string;
    if (!raw) return data;
    try {
      const snapshot = JSON.parse(raw) as OverviewSnapshot;
      // No plugin data is different from a real zero-task snapshot.
      if (snapshot.observedAt <= 0) { data.detail = '等待 Harness 插件状态'; return data; }
      data.showCounts = true;
      data.running = WidgetStore.count(snapshot.running);
      data.waiting = WidgetStore.count(snapshot.waiting);
      data.completed = WidgetStore.count(snapshot.completed);
      data.failed = WidgetStore.count(snapshot.failed);
      data.detail = snapshot.unknown > 0 ? '部分任务状态待确认' : '最近观测状态 · 非实时';
    } catch (_) { data.detail = '打开应用重新同步'; }
    return data;
  }

  private static count(value: number): string {
    return value > 999 ? '999+' : Math.max(0, Math.floor(value)).toString();
  }

  static async publish(context: common.Context): Promise<void> {
    const store = WidgetStore.fresh(context, 'pocket-widget-instances');
    const ids = store.getSync('ids', []) as string[];
    const binding = formBindingData.createFormBindingData(WidgetStore.data(context));
    for (const id of ids) {
      // Transient update errors retain IDs for the next update; removal is owned
      // by onRemoveForm, not by a provider error with uncertain semantics.
      try { await formProvider.updateForm(id, binding); } catch (_) {}
    }
  }
}
