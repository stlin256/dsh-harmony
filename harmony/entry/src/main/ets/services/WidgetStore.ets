import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';

export class WidgetData {
  headline: string = '连接工作空间';
  detail: string = '打开应用，连接你的 Harness';
  stamp: string = '尚未同步';
  showCounts: boolean = false;
  showTasks: boolean = false;
  stale: boolean = false;
  redacted: boolean = false;
  tasks: string = '[]';
  running: string = '—';
  waiting: string = '—';
  completed: string = '—';
  failed: string = '—';
  primarySessionId: string = '';
}

export class OverviewSnapshot {
  running: number = 0;
  waiting: number = 0;
  completed: number = 0;
  failed: number = 0;
  unknown: number = 0;
  observedAt: number = 0;
  generatedAt: number = 0;
  tasks: WidgetTask[] = [];
}

export class WidgetTask {
  sessionId: string = '';
  title: string = '';
  state: string = '';
  updatedAt: number = 0;
}

/** Separate single-writer files: UI writes snapshots; extension writes instance
 * IDs. Refresh Preferences' process-local cache before every cross-process read. */
export class WidgetStore {
  private static pending: Promise<void> = Promise.resolve();
  private static published: Map<string, string> = new Map<string, string>();

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
  private static sortedTasks(tasks: WidgetTask[]): WidgetTask[] {
    const priority: string[] = ['waiting', 'running', 'failed', 'completed', 'unknown'];
    return tasks.slice().sort((left: WidgetTask, right: WidgetTask): number => {
      const order = priority.indexOf(left.state) - priority.indexOf(right.state);
      return order || right.updatedAt - left.updatedAt;
    });
  }

  static register(context: common.Context, id: string): void {
    if (!/^[0-9]{1,32}$/.test(id)) return;
    WidgetStore.published.delete(id);
    const store = WidgetStore.fresh(context, 'pocket-widget-instances');
    const ids = store.getSync('ids', []) as string[];
    if (!ids.includes(id)) { ids.push(id); store.putSync('ids', ids); store.flushSync(); }
  }

  static remove(context: common.Context, id: string): void {
    WidgetStore.published.delete(id);
    const store = WidgetStore.fresh(context, 'pocket-widget-instances');
    const ids = (store.getSync('ids', []) as string[]).filter((item: string) => item !== id);
    store.putSync('ids', ids);
    store.flushSync();
  }

  static detailsEnabled(context: common.Context): boolean {
    return WidgetStore.fresh(context, 'pocket-widget-snapshot').getSync('taskNames', true) === true;
  }

  static async setDetails(context: common.Context, enabled: boolean): Promise<void> {
    await WidgetStore.enqueue(async (): Promise<void> => {
      const store = WidgetStore.fresh(context, 'pocket-widget-snapshot');
      store.putSync('taskNames', enabled);
      const raw = store.getSync('snapshot', '') as string;
      if (raw) {
        try {
          const snapshot = JSON.parse(raw) as OverviewSnapshot;
          snapshot.tasks = enabled ? snapshot.tasks : [];
          store.putSync('snapshot', JSON.stringify(snapshot));
        } catch (_) {
          store.putSync('snapshot', '');
          store.putSync('syncedAt', 0);
        }
      }
      store.flushSync();
      await WidgetStore.publish(context);
    });
  }

  static async update(context: common.Context, snapshot: OverviewSnapshot): Promise<void> {
    await WidgetStore.enqueue(async (): Promise<void> => {
      const store = WidgetStore.fresh(context, 'pocket-widget-snapshot');
      store.putSync('connected', true);
      store.putSync('syncedAt', Date.now());
      const safe = new OverviewSnapshot();
      safe.running = snapshot.running;
      safe.waiting = snapshot.waiting;
      safe.completed = snapshot.completed;
      safe.failed = snapshot.failed;
      safe.unknown = snapshot.unknown;
      safe.observedAt = snapshot.observedAt;
      safe.generatedAt = snapshot.generatedAt;
      safe.tasks = store.getSync('taskNames', true) === true ?
        WidgetStore.sortedTasks(snapshot.tasks).slice(0, 6) : [];
      store.putSync('snapshot', JSON.stringify(safe));
      store.flushSync();
      await WidgetStore.publish(context);
    });
  }

  static async clear(context: common.Context): Promise<void> {
    await WidgetStore.enqueue(async (): Promise<void> => {
      const store = WidgetStore.fresh(context, 'pocket-widget-snapshot');
      store.putSync('connected', false);
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
    const stale = Date.now() < time || Date.now() - time > 15 * 60000;
    const raw = store.getSync('snapshot', '') as string;
    if (!raw) {
      if (stale) {
        data.stale = true;
        data.detail = '快照已过期，打开应用更新';
      }
      return data;
    }
    try {
      const snapshot = JSON.parse(raw) as OverviewSnapshot;
      // No plugin data is different from a real zero-task snapshot.
      if (snapshot.observedAt <= 0) { data.detail = '等待 Harness 插件状态'; return data; }
      data.showCounts = true;
      data.running = WidgetStore.count(snapshot.running);
      data.waiting = WidgetStore.count(snapshot.waiting);
      data.completed = WidgetStore.count(snapshot.completed);
      data.failed = WidgetStore.count(snapshot.failed);
      const details = WidgetStore.detailsEnabled(context);
      data.redacted = !details || stale;
      const tasks = details && !stale && Array.isArray(snapshot.tasks) ? WidgetStore.sortedTasks(snapshot.tasks.filter(item => item &&
        /^[A-Za-z0-9_-]{1,160}$/.test(item.sessionId) && typeof item.title === 'string' && item.title.length > 0)).slice(0, 4) : [];
      if (tasks.length) {
        data.showTasks = true;
        data.tasks = JSON.stringify(tasks);
        data.primarySessionId = tasks[0].sessionId;
      }
      if (stale) {
        data.stale = true;
        data.detail = '快照已过期，打开应用更新';
      } else {
        data.detail = snapshot.unknown > 0 ? '部分状态待确认' : '最近观测';
      }
    } catch (_) { data.detail = '打开应用重新同步'; }
    return data;
  }

  private static count(value: number): string {
    return value > 999 ? '999+' : Math.max(0, Math.floor(value)).toString();
  }

  static async publish(context: common.Context): Promise<void> {
    const store = WidgetStore.fresh(context, 'pocket-widget-instances');
    const ids = store.getSync('ids', []) as string[];
    const data = WidgetStore.data(context);
    const signature = JSON.stringify(data);
    const binding = formBindingData.createFormBindingData(data);
    for (const id of ids) {
      // Transient update errors retain IDs for the next update; removal is owned
      // by onRemoveForm, not by a provider error with uncertain semantics.
      if (WidgetStore.published.get(id) === signature) continue;
      try {
        await formProvider.updateForm(id, binding);
        WidgetStore.published.set(id, signature);
      } catch (_) {}
    }
  }
}
