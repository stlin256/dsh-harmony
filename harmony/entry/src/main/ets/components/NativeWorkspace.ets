import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NativeHarnessClient, NativeHttpError, NativeImageDraft } from '../services/NativeHarnessClient';
import { NativeFrame, NativeMessage, NativeSession, NativeSessionModel, NativePendingQuestion, NativeWorkspaceItem, NativeWorkspaceSnapshot, nativeWorkspaceSessions, nativeToolsParent } from '../services/NativeSessionModel';
import { NativeListSource } from '../services/NativeListSource';
import { NativeExperience } from '../services/NativeExperience';
import { NativeTextContent } from './NativeTextContent';
import { NativeInteraction } from './NativeInteraction';
import { NativeSessionTools } from './NativeSessionTools';
import { NativeMessageView } from './NativeMessageView';
import { DSHIcon } from './DSHIcon';
import { NativeProcessView } from './NativeProcessView';
import { nativeTranscript, nativePresentTranscript } from '../services/NativeTranscript';
import { NativeWorkspacePicker } from './NativeWorkspacePicker';
import { BackgroundMonitor } from '../services/BackgroundMonitor';
import { NativeActionMenu } from './NativeActionMenu';
import { NativeNavigationState, nativeSessionMenu, nativeCanGoBack, nativeForkTitle } from '../services/NativeNavigation';

class MessageSource implements IDataSource {
  private rows: NativeMessage[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): NativeMessage { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener); }
  set(rows: NativeMessage[]): void {
    const append = rows.length === this.rows.length + 1 && this.rows.every((item: NativeMessage, index: number) => item.id === rows[index].id);
    this.rows = rows;
    this.listeners.forEach((item: DataChangeListener) => {
      if (append) item.onDataAdded(rows.length - 1); else item.onDataReloaded();
    });
  }
}

@Component
export struct NativeWorkspace {
  client: NativeHarnessClient = new NativeHarnessClient('');
  context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  supportsPush: boolean = false;
  onLogin: () => void = (): void => {};
  onSettings: () => void = (): void => {};
  onSnapshot: (value: string) => Promise<void> = async (): Promise<void> => {};
  onLocalNotification: (sessionId: string, title: string, state: string) => Promise<void> = async (): Promise<void> => {};
  onCompatibility: () => void = (): void => {};
  @StorageLink('nativeBackRevision') @Watch('backToSessions') private backRevision: number = 0;
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeHostSettingsRevision') @Watch('preferencesChanged') private preferencesRevision: number = 0;
  @StorageLink('nativeModelRevision') @Watch('modelCaptionChanged') private modelRevision: number = 0;
  @StorageLink('nativeRefreshRevision') @Watch('reload') private refreshRevision: number = 0;
  @StorageLink('nativeCompatibilityActive') @Watch('activityChanged') private fallbackActive: boolean = false;
  @StorageLink('nativeAppActive') @Watch('activityChanged') private active: boolean = true;
  @StorageLink('nativeBackgroundMonitor') @Watch('activityChanged') private backgroundMonitor: boolean = false;
  @StorageLink('requestedSession') @Watch('openRequested') private requestedSession: string = '';
  @State @Watch('sessionsChanged') private sessions: NativeSession[] = [];
  @State private continued: NativeFrame[] = [];
  @State private interactions: NativeFrame[] = [];
  @State private images: NativeImageDraft[] = [];
  @State private attaching: boolean = false;
  @State @Watch('navigationChanged') private toolsOpen: boolean = false;
  @State private toolsId: string = '';
  @State @Watch('navigationChanged') private menuId: string = '';
  @State private menuTarget: string = '';
  @State @Watch('navigationChanged') private utilityOpen: boolean = false;
  @State private copying: boolean = false;
  @State private modelCaption: string = '模型';
  @State private groupHeight: number = 400;
  @State private downloading: boolean = false;
  @State private menuBusy: boolean = false;
  @State private archivedUndo: string = '';
  @State private steer: boolean = false;
  @State @Watch('navigationChanged') private newSessionOpen: boolean = false;
  @State @Watch('navigationChanged') private workspacePickerOpen: boolean = false;
  @State @Watch('sessionsChanged') private workspaces: NativeWorkspaceSnapshot = new NativeWorkspaceSnapshot();
  @State @Watch('sessionsChanged') private workspaceId: string = '';
  @State @Watch('sessionsChanged') private query: string = '';
  @State private newWorkspaceId: string = '';
  @State private newCwd: string = '';
  @State private newPreset: string = '';
  @State private selected: string = '';
  @State private title: string = '工作空间';
  @State private draft: string = '';
  @State @Watch('navigationChanged') private showSessions: boolean = true;
  @State @Watch('navigationChanged') private wide: boolean = false;
  @State private loading: boolean = true;
  @State private sending: boolean = false;
  @State private connected: boolean = false;
  @State private running: boolean = false;
  @State private waiting: boolean = false;
  @State private uncertain: boolean = false;
  @State private reconnecting: boolean = false;
  @State private error: string = '';
  @State private paging: boolean = false;
  @State private hasMore: boolean = false;
  @State private visibleSessionCount: number = 0;
  @State private streamText: string = '';
  @State private streamReasoning: string = '';
  private sessionSource: NativeListSource<NativeSession> = new NativeListSource<NativeSession>();
  private source: MessageSource = new MessageSource();
  private scroller: Scroller = new Scroller();
  private model: NativeSessionModel = new NativeSessionModel();
  private previousRows: NativeMessage[] = [];
  private followTail: boolean = true;
  private mounted: boolean = false;
  private generation: number = 0;
  private paintTimer: number = -1;
  private reconnectTimer: number = -1;
  private retries: number = 0;
  private widgetTimer: number = -1;
  private backgroundTimer: number = -1;
  private backgroundActive: boolean = false;
  private backgroundBusy: boolean = false;
  private backgroundStates: Map<string, string> = new Map<string, string>();
  private openTurns: Set<string> = new Set<string>();

  private preferencesChanged(): void { this.steer = this.client.hostSettings.chat().busyEnter === 'steer'; this.renderTranscript(); }
  private modelCaptionChanged(): void { this.modelCaption = this.client.modelDirectory.caption(this.selected); }

  private navigationChanged(): void {
    const state = new NativeNavigationState();
    state.wide = this.wide; state.sessions = this.showSessions; state.picker = this.workspacePickerOpen;
    state.create = this.newSessionOpen; state.tools = this.toolsOpen; state.menu = !!this.menuId || this.utilityOpen;
    AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', nativeCanGoBack(state));
  }

  private sessionsChanged(): void {
    const visible = nativeWorkspaceSessions(this.sessions, this.workspaces, this.workspaceId, this.query, this.client.models, this.selected);
    this.visibleSessionCount = visible.length;
    this.sessionSource.set(visible);
  }
  aboutToAppear(): void { this.mounted = true; this.reload(); }
  aboutToDisappear(): void {
    this.mounted = false; this.generation++; this.client.pause();
    clearTimeout(this.paintTimer); clearTimeout(this.reconnectTimer); clearTimeout(this.widgetTimer); clearTimeout(this.backgroundTimer);
    this.stopBackground();
    AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', false);
  }
  private async reload(): Promise<void> {
    const generation = ++this.generation;
    this.loading = true; this.error = '';
    try {
      const state = await this.client.state();
      if (!this.mounted || generation !== this.generation) return;
      if (!state.authenticated) { this.onLogin(); return; }
      const value = await this.client.sessions();
      if (!this.mounted || generation !== this.generation) return;
      if (value.protocol !== 2) throw new Error('请升级网关或使用兼容模式');
      this.sessions = value.items;
      this.refreshWorkspaces();
      this.client.hostSettings.refresh().catch(() => {});
      this.updateWidget();
      const requested = this.requestedSession || this.client.selectedId;
      if (requested) {
        this.requestedSession = '';
        if (requested === this.selected) {
          const session = this.sessions.find((item: NativeSession) => item.id === requested);
          if (session) this.title = session.title.trim() || '未命名会话';
          this.follow();
        } else this.select(requested);
      }
    } catch (error) {
      this.handleError(error as Error);
      if (!(error instanceof NativeHttpError && error.status === 401)) this.scheduleReconnect('');
    }
    finally { if (this.mounted && generation === this.generation) this.loading = false; }
  }
  private handleError(error: Error): void {
    if (!this.mounted) return;
    if (error instanceof NativeHttpError && error.status === 401) { this.onLogin(); return; }
    this.error = error.message || '连接失败，请刷新或使用兼容模式';
  }
  private activityChanged(): void {
    clearTimeout(this.reconnectTimer); clearTimeout(this.widgetTimer);
    if (!this.active || this.fallbackActive) {
      this.interactions = []; this.client.pause(); this.connected = false;
      if (this.backgroundMonitor && !this.supportsPush && !this.fallbackActive) this.pollBackground(true);
      else this.stopBackground();
      return;
    }
    this.stopBackground();
    this.updateWidget();
    if (this.selected) this.follow(); else this.reload();
  }
  private animatePane(action: () => void): void {
    if (NativeExperience.reducedMotion()) action();
    else this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, action);
  }
  private backToSessions(): void {
    if (this.menuId || this.utilityOpen) { this.menuId = ''; this.utilityOpen = false; return; }
    if (this.workspacePickerOpen) { this.workspacePickerOpen = false; return; }
    if (this.newSessionOpen) { this.newSessionOpen = false; return; }
    if (this.toolsOpen) {
      const parent = nativeToolsParent(AppStorage.get<string>('nativeSessionToolsPage') || 'root');
      if (parent) AppStorage.setOrCreate<string>('nativeSessionToolsPage', parent);
      else this.toolsOpen = false;
      return;
    }
    this.animatePane(() => { this.toolsOpen = false; this.showSessions = true; });
    this.navigationChanged();
  }
  private openTools(page: string, id: string = this.selected): void {
    this.toolsId = id; AppStorage.setOrCreate<string>('nativeSessionToolsPage', page); this.toolsOpen = true;
  }
  private async refreshSessionList(): Promise<void> {
    const rows = await this.client.sessions();
    if (this.mounted) { this.sessions = rows.items; await this.refreshWorkspaces(); }
  }
  private async sessionAction(action: string): Promise<void> {
    const id = this.menuTarget; this.menuId = '';
    if (!id || this.menuBusy) return;
    if (action === 'rename') { this.openTools('rename', id); return; }
    if (action === 'copyId') {
      pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, id))
        .then(() => { this.getUIContext().getPromptAction().showToast({ message: '已复制' }); }).catch(() => { this.error = '复制失败'; });
      return;
    }
    this.menuBusy = true;
    try {
      if (action === 'fork') {
        const reply = JSON.parse(await this.client.operation(JSON.stringify({ operation: 'fork', sessionId: id }))) as Record<string, Object>;
        const source = this.sessions.find((item: NativeSession) => item.id === id);
        try {
          if (source?.titleKnown && typeof reply.sessionId === 'string') await this.client.operation(JSON.stringify({ operation: 'rename', sessionId: reply.sessionId, title: nativeForkTitle(source.title) }));
        } catch (_) { this.error = '分支已创建，标题更新失败'; }
        await this.refreshSessionList(); return;
      }
      try { await this.client.operation(JSON.stringify({ operation: action, sessionId: id })); }
      catch (error) {
        if (action !== 'archive' || !(error instanceof NativeHttpError) || error.code !== 'workspace/session-active') throw error as Error;
        const choice = await this.getUIContext().getPromptAction().showDialog({ title: '停止活动并归档？',
          buttons: [{ text: '取消', color: '#777A80' }, { text: '停止并归档', color: '#C53737' }] });
        if (choice.index !== 1) return;
        await this.client.operation(JSON.stringify({ operation: 'archive', sessionId: id, stopActivity: true }));
      }
      if (!this.mounted) return;
      if (action === 'archive') {
        this.archivedUndo = id;
        if (this.selected === id) { this.client.pause(); this.selected = ''; this.client.selectedId = ''; this.showSessions = true; }
      }
      await this.refreshSessionList();
    } catch (error) { this.handleError(error as Error); }
    finally { this.menuBusy = false; }
  }
  private async copyMarkdown(): Promise<void> {
    this.utilityOpen = false; if (this.copying) return;
    const id = this.selected; this.copying = true;
    try {
      const parts: Uint8Array[] = []; let size = 0;
      await this.client.exportSession(id, 'markdown', (part: ArrayBuffer): void => { const bytes = new Uint8Array(part); parts.push(bytes); size += bytes.length; });
      const all = new Uint8Array(size); let offset = 0;
      parts.forEach((part: Uint8Array): void => { all.set(part, offset); offset += part.length; });
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, util.TextDecoder.create('utf-8').decodeToString(all)));
      if (this.mounted) this.getUIContext().getPromptAction().showToast({ message: '已复制 Markdown' });
    } catch (_) { if (this.mounted) this.error = '复制失败'; }
    finally { this.copying = false; }
  }
  private async downloadLog(): Promise<void> {
    this.utilityOpen = false; if (this.downloading) return;
    const id = this.selected; this.downloading = true;
    const path = this.context.cacheDir + '/export-' + util.generateRandomUUID() + '.zip';
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const output = file;
      await this.client.exportSession(id, 'zip', (part: ArrayBuffer): void => { fileIo.writeSync(output.fd, part); });
      fileIo.closeSync(file); file = null;
      if (!this.mounted) return;
      const options = new picker.DocumentSaveOptions(); options.newFileNames = ['dsh-session-' + id + '.zip'];
      const chosen = await new picker.DocumentViewPicker(this.context).save(options);
      if (!chosen.length) return;
      const destination = fileIo.openSync(chosen[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try { fileIo.copyFileSync(path, destination.fd); } finally { fileIo.closeSync(destination); }
      this.getUIContext().getPromptAction().showToast({ message: '日志已保存' });
    } catch (_) { if (this.mounted) this.error = '下载失败'; }
    finally { if (file) fileIo.closeSync(file); try { fileIo.unlinkSync(path); } catch (_) {} this.downloading = false; }
  }
  @Builder
  private sessionMenu() {
    NativeActionMenu({ items: nativeSessionMenu(this.workspaces.pinnedSessionIds.includes(this.menuTarget)), onSelect: (id: string): void => { this.sessionAction(id); } })
  }
  @Builder
  private utilityMenu() {
    NativeActionMenu({ items: [
      { id: 'copy', title: '复制 Markdown', icon: 'copy-outline', disabled: this.copying, danger: false, separator: false },
      { id: 'download', title: '下载日志', icon: 'download-outline', disabled: this.downloading, danger: false, separator: false }
    ], onSelect: (id: string): void => { if (id === 'copy') this.copyMarkdown(); else this.downloadLog(); } })
  }
  private async refreshWorkspaces(): Promise<void> {
    try { const value = await this.client.workspaces(); if (this.mounted && value.available) this.workspaces = value; }
    catch (_) {}
  }
  private openNewSession(): void {
    this.newWorkspaceId = this.workspaceId; this.newCwd = ''; this.newPreset = ''; this.newSessionOpen = true;
  }
  private async updateWidget(): Promise<void> {
    clearTimeout(this.widgetTimer);
    if (!this.mounted || !this.active || this.fallbackActive) return;
    try {
      const value = await this.client.request('/pocket/api/overview');
      if (this.mounted && this.active && !this.fallbackActive) {
        this.rememberBackgroundStates(value);
        await this.onSnapshot(value);
      }
    } catch (_) {}
    finally { if (this.mounted && this.active && !this.fallbackActive) this.widgetTimer = setTimeout(() => { this.updateWidget(); }, 60000); }
  }
  private rememberBackgroundStates(raw: string): void {
    try {
      const data = JSON.parse(raw) as Record<string, Object>;
      const tasks = data.tasks as Array<Record<string, Object>>;
      if (!Array.isArray(tasks)) return;
      for (const task of tasks) {
        if (typeof task.sessionId === 'string' && typeof task.state === 'string') {
          this.backgroundStates.set(task.sessionId, task.state);
        }
      }
    } catch (_) {}
  }
  private knownActiveSession(): string {
    let sessionId = '';
    this.backgroundStates.forEach((state: string, id: string) => {
      if (!sessionId && (state === 'running' || state === 'waiting')) sessionId = id;
    });
    return sessionId;
  }
  private async pollBackground(initial: boolean): Promise<void> {
    if (!this.mounted || this.active || this.fallbackActive || !this.backgroundMonitor || this.supportsPush || this.backgroundBusy) return;
    this.backgroundBusy = true;
    try {
      if (initial && !this.backgroundActive) {
        const known = this.knownActiveSession();
        if (known) {
          try { await BackgroundMonitor.start(this.context, known); this.backgroundActive = true; } catch (_) {}
        }
      }
      const raw = await this.client.request('/pocket/api/overview');
      if (!this.mounted || this.active || this.fallbackActive || !this.backgroundMonitor) return;
      const data = JSON.parse(raw) as Record<string, Object>;
      const tasks = data.tasks as Array<Record<string, Object>>;
      if (!Array.isArray(tasks)) return;
      for (const task of tasks) {
        if (typeof task.sessionId !== 'string' || typeof task.state !== 'string') continue;
        const id = task.sessionId;
        const state = task.state;
        const previous = this.backgroundStates.get(id) || '';
        if (previous && previous !== state && (state === 'waiting' || state === 'completed' || state === 'failed') &&
          (previous === 'running' || previous === 'waiting')) {
          const title = typeof task.title === 'string' ? task.title : '任务';
          await this.onLocalNotification(id, title, state);
        }
        this.backgroundStates.set(id, state);
      }
      const active = tasks.filter((task: Record<string, Object>) => task.state === 'running' || task.state === 'waiting');
      if (!active.length) { this.stopBackground(); return; }
      if (!this.backgroundActive) {
        const first = active[0].sessionId as string;
        await BackgroundMonitor.start(this.context, first);
        this.backgroundActive = true;
      }
      clearTimeout(this.backgroundTimer);
      this.backgroundTimer = setTimeout(() => { this.pollBackground(false); }, 30000);
    } catch (_) {
      if (this.backgroundActive && this.mounted && !this.active && this.backgroundMonitor) {
        clearTimeout(this.backgroundTimer);
        this.backgroundTimer = setTimeout(() => { this.pollBackground(false); }, 30000);
      }
    } finally { this.backgroundBusy = false; }
  }
  private stopBackground(): void {
    clearTimeout(this.backgroundTimer); this.backgroundTimer = -1;
    if (!this.backgroundActive) return;
    this.backgroundActive = false;
    BackgroundMonitor.stop(this.context).catch(() => {});
  }
  private openRequested(): void {
    if (!this.requestedSession) return;
    const id = this.requestedSession; this.requestedSession = ''; this.select(id);
  }
  private select(id: string): void {
    if (this.selected) this.client.models.set(this.selected, this.model);
    this.client.drafts.set(this.selected, this.draft);
    this.continued = []; this.interactions = []; this.toolsOpen = false; this.client.selectedId = id;
    const session = this.sessions.find((item: NativeSession) => item.id === id);
    this.title = session ? session.title.trim() || '未命名会话' : '会话';
    this.draft = this.client.drafts.get(id) || '';
    this.images = this.client.images.get(id) || [];
    this.uncertain = this.client.uncertain.has(id);
    this.animatePane(() => { this.selected = id; this.showSessions = false; }); this.followTail = true;
    this.navigationChanged();
    this.model = this.client.models.get(id) || new NativeSessionModel();
    this.client.models.set(id, this.model);
    this.previousRows = this.model.messages;
    this.renderTranscript();
    this.streamText = ''; this.streamReasoning = '';
    this.running = false; this.waiting = false; this.retries = 0;
    this.reconnecting = true;
    this.hydrateHistory(id);
    this.follow();
    this.client.modelDirectory.load(id).catch(() => {});
  }
  private async hydrateHistory(id: string): Promise<void> {
    if (!this.mounted || this.model.messages.length > 0) return;
    try {
      const page = await this.client.page(id, Number.MAX_SAFE_INTEGER);
      if (!this.mounted || this.selected !== id || this.model.messages.length > 0) return;
      this.model.prepend(page);
      this.paint();
    } catch (_) {
      // Keep the last in-memory snapshot visible while the live channel retries.
    }
  }
  private follow(): void {
    if (!this.mounted || !this.active || this.fallbackActive || !this.selected) return;
    clearTimeout(this.reconnectTimer);
    const id = this.selected;
    this.connected = false;
    this.client.follow(id, (frame: NativeFrame): void => {
      if (!this.mounted || this.selected !== id) return;
      if (frame.type === 'questions') {
        this.continued = frame.questions.map((question: NativePendingQuestion) => {
          const value = new NativeFrame(); value.eventId = 'continued-' + question.callId;
          value.callId = question.callId; value.connectionId = id;
          value.interaction = 'user-questions/request'; value.request.questions = question.questions;
          return value;
        }); return;
      }
      if (frame.type === 'interaction') {
        this.interactions = this.interactions.filter((item: NativeFrame) => item.eventId !== frame.eventId).concat([frame]); return;
      }
      if (frame.type === 'interaction-ended') {
        this.interactions = this.interactions.filter((item: NativeFrame) => item.eventId !== frame.eventId); return;
      }
      if (frame.type === 'error') {
        // Preserve the server's close/reconnect lifecycle instead of throwing
        // through the WebSocket parser and misreporting an invalid JSON frame.
        console.error('DSH Harmony live stream returned an error frame');
        this.connected = false; this.reconnecting = true;
        return;
      }
      this.model.apply(frame);
      if (frame.type === 'snapshot') {
        this.connected = true; this.reconnecting = false; this.error = ''; this.retries = 0;
      }
      if (this.paintTimer < 0) this.paintTimer = setTimeout(() => { this.paintTimer = -1; this.paint(); }, 40);
    }, (reason: string): void => {
      console.error('DSH Harmony live socket ended: ' + reason);
      this.reconnect(id);
    }).catch((): void => { this.scheduleReconnect(id); });
  }
  private async reconnect(id: string): Promise<void> {
    if (!this.mounted || !this.active || this.fallbackActive || this.selected !== id) return;
    this.connected = false;
    try {
      const state = await this.client.state();
      if (!this.mounted || !this.active || this.fallbackActive || this.selected !== id) return;
      if (!state.authenticated) { this.onLogin(); return; }
    } catch (_) {}
    if (!this.mounted || !this.active || this.fallbackActive || this.selected !== id) return;
    this.scheduleReconnect(id);
  }
  private scheduleReconnect(id: string): void {
    if (!this.mounted || !this.active || this.fallbackActive || (id && this.selected !== id)) return;
    clearTimeout(this.reconnectTimer);
    this.interactions = [];
    this.connected = false; this.reconnecting = true; this.error = '';
    this.retries++;
    const delay = Math.min(30000, 1000 * Math.pow(2, Math.min(this.retries, 5)));
    this.reconnectTimer = setTimeout(() => { if (id) this.follow(); else this.reload(); }, delay);
  }
  private paint(): void {
    if (!this.mounted) return;
    this.previousRows = this.model.messages; this.renderTranscript();
    this.running = this.model.running; this.waiting = this.model.waiting; this.hasMore = this.model.hasMore;
    this.sessionsChanged();
    this.streamText = this.model.streamText; this.streamReasoning = this.model.streamReasoning;
    if (this.followTail) setTimeout(() => { if (this.mounted) this.scroller.scrollEdge(Edge.Bottom); }, 0);
  }
  private renderTranscript(): void {
    const rows = nativeTranscript(this.model.messages, this.model.running, this.model.streamTools, this.model.streamReasoning, this.model.streamText);
    const visible = nativePresentTranscript(rows, this.client.hostSettings.chat(), this.model.turnDisclosure, this.model.collapseThrough);
    this.openTurns = new Set<string>(visible.filter((row: NativeMessage) => row.role === 'process').map((row: NativeMessage) => row.turnKey));
    this.source.set(visible);
  }
  private toggleTurn(key: string): void {
    const next = !this.openTurns.has(key);
    this.model.turnDisclosure.set(key, next);
    if (!next) this.model.disclosures.forEach((_value: boolean, id: string): void => { if (id.startsWith(key + '|')) this.model.disclosures.delete(id); });
    this.renderTranscript();
  }
  private async createSession(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    try {
      const workspace = this.workspaces.items.find((item: NativeWorkspaceItem) => item.workspaceId === this.newWorkspaceId);
      const reusable = !this.newPreset && workspace ? this.sessions.find((item: NativeSession) => item.blank === true && workspace.sessionIds.includes(item.id) && !this.workspaces.archivedSessionIds.includes(item.id)) : undefined;
      const id = await this.client.create(this.newCwd, this.newPreset, this.newWorkspaceId, reusable?.id || '');
      this.workspaceId = this.newWorkspaceId;
      this.newSessionOpen = false;
      if (!this.mounted) return;
      const value = await this.client.sessions();
      this.sessions = value.items; this.refreshWorkspaces(); this.select(id);
    } catch (error) { this.handleError(error as Error); }
    finally { this.loading = false; }
  }
  private async send(): Promise<void> {
    if (this.sending || (!this.draft.trim() && !this.images.length) || !this.selected || this.uncertain) return;
    const id = this.selected; const text = this.draft;
    if (!this.running && this.client.hostSettings.chat().collapseTiming === 'next-input') { this.model.collapseThrough = this.model.lastSeq(); this.renderTranscript(); }
    this.sending = true; this.error = '';
    this.client.drafts.set(id, text);
    try {
      await this.client.prompt(id, text, this.steer ? 'steer' : 'queue', this.images);
      this.client.drafts.set(id, ''); this.client.images.delete(id);
      if (this.selected === id) this.images = [];
      if (this.selected === id) this.draft = '';
    } catch (error) { if (this.selected === id) { this.uncertain = this.client.uncertain.has(id); this.handleError(error as Error); } }
    finally { this.sending = false; }
  }
  private async attach(): Promise<void> {
    if (this.attaching || !this.selected) return;
    const id = this.selected; this.attaching = true; this.error = '';
    try {
      const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uris = await new picker.DocumentViewPicker(context).select(options);
      if (!uris.length || !this.mounted) return;
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      const chunks: Uint8Array[] = []; let size: number = 0;
      try {
        while (true) {
          const buffer = new ArrayBuffer(65536);
          const count = fileIo.readSync(file.fd, buffer);
          if (count === 0) break;
          chunks.push(new Uint8Array(buffer, 0, count)); size += count;
          // Yield between disk windows so the native UI can keep animating.
          await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 0); });
          if (!this.mounted) return;
        }
      } finally { fileIo.closeSync(file); }
      const bytes = new Uint8Array(size); let offset: number = 0;
      chunks.forEach((part: Uint8Array) => { bytes.set(part, offset); offset += part.length; });
      const draft = new NativeImageDraft(); draft.id = util.generateRandomUUID();
      if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) draft.mediaType = 'image/png';
      else if (bytes[0] === 0xFF && bytes[1] === 0xD8) draft.mediaType = 'image/jpeg';
      else if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) draft.mediaType = 'image/gif';
      else if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) draft.mediaType = 'image/webp';
      else throw new Error('请选择 PNG、JPEG、GIF 或 WebP 图片；其他附件请使用完整工作空间');
      draft.data = new util.Base64Helper().encodeToStringSync(bytes);
      draft.name = '图片 ' + ((this.client.images.get(id) || []).length + 1);
      const images = (this.client.images.get(id) || []).concat([draft]);
      this.client.images.set(id, images); if (this.selected === id) this.images = images;
    } catch (error) { this.handleError(error as Error); }
    finally { this.attaching = false; }
  }
  private async older(): Promise<void> {
    if (this.paging || !this.hasMore || this.model.historyBefore < 0) return;
    this.paging = true;
    this.followTail = false;
    try {
      const id = this.selected;
      const page = await this.client.page(id, this.model.historyBefore, this.model.historyCut);
      if (this.selected !== id || !this.mounted) return;
      const previousCount = this.model.messages.length;
      this.model.prepend(page); this.paint();
      this.scroller.scrollToIndex(this.model.messages.length - previousCount + (this.model.hasMore ? 1 : 0), false);
    } catch (error) { this.handleError(error as Error); }
    finally { this.paging = false; }
  }

  @Builder
  private sessionList() {
    Column({ space: 8 }) {
      Row() {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            DSHIcon({ glyph: 'browse-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 16 })
            Text(this.workspaces.items.find((item: NativeWorkspaceItem) => item.workspaceId === this.workspaceId)?.title || '全部工作区')
              .fontSize(15).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
            DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 }).rotate({ angle: -90 })
          }.width('100%')
        }.height(36).layoutWeight(1).padding({ left: 0, right: 6 }).backgroundColor(Color.Transparent)
          .onClick(() => { this.workspacePickerOpen = true; })
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'new-chat-outline', color: this.dark ? '#F9FAFB' : '#0F1115' })
        }.width(36).height(36).borderRadius(18)
          .backgroundColor(this.dark ? '#353638' : '#EBEEF2').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .accessibilityText('新建会话').enabled(!this.loading).onClick(() => { this.openNewSession(); })
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'settings-outline', color: this.dark ? '#CFD3D6' : '#61666B' })
        }.width(36).height(36).borderRadius(18)
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .accessibilityText('应用设置').onClick(() => { this.onSettings(); })
      }.width('100%')
      TextInput({ text: this.query, placeholder: '搜索会话' }).height(34).fontSize(13).borderRadius(9)
        .backgroundColor(this.dark ? '#232324' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        .onChange((value: string) => { this.query = value; })
      List({ space: 2 }) {
        LazyForEach(this.sessionSource, (item: NativeSession) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(item.title.trim() || '未命名会话').fontSize(14).maxLines(1).layoutWeight(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
              if (item.running) {
                Text('运行中').fontSize(10).fontColor(this.dark ? '#C7D8FF' : '#3B5B9A')
              }
              if (this.workspaces.pinnedSessionIds.includes(item.id)) {
                DSHIcon({ glyph: 'pin-fill', glyphSize: 12, color: this.dark ? '#93969B' : '#8A8D91' })
              }
              if (item.blank !== true) {
                Button({ type: ButtonType.Normal }) { DSHIcon({ glyph: 'ellipsis-outline', color: this.dark ? '#93969B' : '#8A8D91' }) }
                  .width(32).height(32).padding(6).borderRadius(10).backgroundColor(Color.Transparent).enabled(!this.menuBusy)
                  .accessibilityText(item.title + '，会话操作').onClick(() => { this.menuTarget = item.id; this.menuId = item.id; })
                  .bindPopup(this.menuId === item.id, { builder: this.sessionMenu, placement: Placement.BottomRight,
                    enableArrow: false, targetSpace: 4, radius: 16, mask: true,
                    popupColor: this.dark ? '#37383C' : '#F8F9FA', backgroundBlurStyle: BlurStyle.NONE,
                    onStateChange: (event): void => { if (!event.isVisible && this.menuId === item.id) this.menuId = ''; } })
              }
            }.padding({ left: 10, right: 4, top: 2, bottom: 2 }).width('100%').borderRadius(10)
              .backgroundColor(this.selected === item.id ? this.dark ? '#2C2C2E' : '#EBEEF2' : Color.Transparent)
          }.onClick(() => this.select(item.id)).accessibilityText(item.title + (item.running ? '，运行中' : ''))
        }, (item: NativeSession) => item.id)
      }.layoutWeight(1).width('100%')
      if (this.reconnecting) {
          Text('连接中断，正在尝试重连').fontSize(11).padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .width('100%').borderRadius(9).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7')
      }
      if (this.loading) { Text('正在连接…').fontSize(13).fontColor(this.dark ? '#CFD3D6' : '#61666B') }
      if (!this.loading && !this.visibleSessionCount) { Text('新建会话，开始你的任务').fontSize(13).fontColor(this.dark ? '#CFD3D6' : '#61666B') }
    }.padding({ left: 12, right: 12, top: 8, bottom: 8 }).height('100%').width(this.wide ? 240 : '100%')
      .backgroundColor(this.dark ? '#151517' : '#FFFFFF').transition(TransitionEffect.OPACITY)
  }

  @Builder
  private conversation() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        if (!this.wide) {
          Button({ type: ButtonType.Normal }) {
            DSHIcon({ glyph: 'panel-left-outline', color: this.dark ? '#F9FAFB' : '#0F1115' })
          }.width(36).height(36).borderRadius(10)
            .backgroundColor(Color.Transparent).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
            .accessibilityText('会话列表')
            .onClick(() => { this.backToSessions(); })
        }
        Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'ellipsis-outline', color: this.dark ? '#CFD3D6' : '#61666B' })
        }.width(36).height(36).borderRadius(10)
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .accessibilityText('更多操作').onClick(() => { this.utilityOpen = !this.utilityOpen; })
          .bindPopup(this.utilityOpen, { builder: this.utilityMenu, placement: Placement.BottomRight,
            enableArrow: false, targetSpace: 4, radius: 16, mask: true,
            popupColor: this.dark ? '#37383C' : '#F8F9FA', backgroundBlurStyle: BlurStyle.NONE,
            onStateChange: (event): void => { if (!event.isVisible) this.utilityOpen = false; } })
      }.width('100%')
      if (this.reconnecting) {
        Row({ space: 8 }) {
          Text('•').fontSize(14).fontColor(this.dark ? '#F8C86A' : '#A56A00')
          Text('连接中断，正在尝试重连').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          Blank()
        }.padding({ left: 10, right: 10, top: 6, bottom: 6 }).width('100%').borderRadius(9)
          .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7')
      }
      List({ space: 12, scroller: this.scroller }) {
        if (this.hasMore) { ListItem() { Button(this.paging ? '正在加载…' : '加载更早消息').enabled(!this.paging).height(38).onClick(() => { this.older(); }) } }
        LazyForEach(this.source, (message: NativeMessage) => {
          ListItem() {
            if (message.role === 'process') {
              NativeProcessView({ client: this.client, sessionId: this.selected, message, disclosures: this.model.disclosures, maxGroupHeight: this.groupHeight })
            } else if (message.role === 'turn-control') {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 }) {
                  DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 })
                    .rotate({ angle: this.openTurns.has(message.turnKey) ? -90 : 180 })
                  Text(message.label).fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91')
                }
              }.height(30).padding(0).backgroundColor(Color.Transparent).enabled(message.foldable).onClick(() => { this.toggleTurn(message.turnKey); })
            } else if (message.role === 'turn-footer') {
              Text(message.label + (message.text ? ' · ' + message.text : '')).fontSize(11)
                .fontColor(message.outcome === 'error' ? '#D55E5E' : this.dark ? '#93969B' : '#8A8D91')
            } else { Row() {
              if (message.role === 'user') { Blank().layoutWeight(1) }
              NativeMessageView({ client: this.client, sessionId: this.selected, message: message, onCompatibility: this.onCompatibility })
            }.width('100%').alignItems(VerticalAlign.Top) }
          }
        }, (message: NativeMessage) => message.id)
      }.layoutWeight(1).width('100%').cachedCount(6)
        .edgeEffect(NativeExperience.reducedMotion() ? EdgeEffect.None : EdgeEffect.Spring)
        .onReachStart(() => { if (this.hasMore) this.older(); })
        .onScroll(() => { this.followTail = this.scroller.isAtEnd(); })
      ForEach(this.interactions.concat(this.continued), (frame: NativeFrame) => {
        NativeInteraction({ client: this.client, frame, onDone: (): void => {
          this.interactions = this.interactions.filter((item: NativeFrame) => item.eventId !== frame.eventId);
          this.continued = this.continued.filter((item: NativeFrame) => item.eventId !== frame.eventId);
        } })
      }, (frame: NativeFrame) => frame.eventId)
      if (this.waiting && !this.interactions.length && !this.continued.length) {
          Button('有待处理输入 · 打开完整交互', { type: ButtonType.Normal }).height(38).fontSize(12).borderRadius(11)
          .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onClick(this.onCompatibility)
      }
      if (this.uncertain) {
        Button('发送结果未确认 · 已检查会话，允许再次发送', { type: ButtonType.Normal }).height(38).fontSize(11)
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .onClick(() => { this.client.uncertain.delete(this.selected); this.uncertain = false; })
      }
      if (this.images.length) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.images, (image: NativeImageDraft) => {
              Button(image.name + ' ×').height(32).fontSize(11).enabled(!this.sending).onClick(() => {
                this.images = this.images.filter((item: NativeImageDraft) => item.id !== image.id);
                this.client.images.set(this.selected, this.images);
              })
            }, (image: NativeImageDraft) => image.id)
          }
        }.scrollable(ScrollDirection.Horizontal).width('100%')
      }
      Column({ space: 8 }) {
        TextArea({ text: this.draft, placeholder: '发送消息…' }).height(44).enabled(!this.sending)
          .fontSize(14).borderRadius(0).padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onChange((value: string) => { this.draft = value; this.client.drafts.set(this.selected, value); })
        Row({ space: 6 }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 4 }) {
              Text(this.modelCaption).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 10, color: this.dark ? '#93969B' : '#8A8D91' }).rotate({ angle: -90 })
            }.width('100%')
          }.layoutWeight(1).height(32).padding({ left: 3, right: 3 }).backgroundColor(Color.Transparent)
            .fontColor(this.dark ? '#CFD3D6' : '#61666B').accessibilityText('模型与推理').onClick(() => { this.openTools('modelsRoot'); })
          Button({ type: ButtonType.Normal }) {
            if (this.attaching) { LoadingProgress().width(14).height(14).color(this.dark ? '#F9FAFB' : '#0F1115') }
            else { DSHIcon({ glyph: 'plus-outline', color: this.dark ? '#F9FAFB' : '#0F1115' }) }
          }.width(32).height(32).borderRadius(16)
            .backgroundColor(this.dark ? '#353638' : '#EBEEF2').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
            .accessibilityText(this.attaching ? '读取中' : '添加图片')
            .enabled(!this.attaching && !this.sending).onClick(() => { this.attach(); })
          Button({ type: ButtonType.Normal }) {
            DSHIcon({ glyph: 'paperclip-outline', color: this.dark ? '#CFD3D6' : '#61666B' })
          }.width(32).height(32).borderRadius(16)
            .backgroundColor(this.dark ? '#353638' : '#EBEEF2').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
            .accessibilityText('更多附件')
            .onClick(this.onCompatibility)
          if (this.running) { Button({ type: ButtonType.Normal }) {
            Row({ space: 5 }) {
              DSHIcon({ glyph: this.steer ? 'paper-plane-outline' : 'queue-outline', color: this.dark ? '#CFD3D6' : '#61666B', glyphSize: 14 })
              Text(this.steer ? '接管' : '排队').fontSize(11).fontColor(this.dark ? '#CFD3D6' : '#61666B')
            }
          }.height(32).borderRadius(9).backgroundColor(Color.Transparent)
            .accessibilityText(this.steer ? '发送模式：接管' : '发送模式：排队，点击切换')
            .onClick(() => { this.steer = !this.steer; })
          }
          if (this.running && !this.sending && !this.draft.trim() && !this.images.length) {
            Button({ type: ButtonType.Normal }) {
              DSHIcon({ glyph: 'stop-fill', color: '#FFFFFF' })
            }.width(34).height(34).borderRadius(17)
              .backgroundColor(this.dark ? '#679EFE' : '#3964FE').accessibilityText('停止任务')
              .onClick(() => { this.client.cancel(this.selected).catch((error: Error) => this.handleError(error)); })
          } else {
            Button({ type: ButtonType.Normal }) {
              if (this.sending) { LoadingProgress().width(16).height(16).color('#FFFFFF') }
              else { DSHIcon({ glyph: 'send-arrow', color: '#FFFFFF' }) }
            }.width(34).height(34).borderRadius(17)
              .backgroundColor(this.dark ? '#679EFE' : '#3964FE')
              .enabled(this.connected && !this.sending && !this.uncertain && (this.draft.trim().length > 0 || this.images.length > 0))
              .opacity(this.connected && !this.sending && !this.uncertain && (this.draft.trim().length > 0 || this.images.length > 0) ? 1 : 0.4)
              .accessibilityText(this.sending ? '发送中' : '发送').onClick(() => { this.followTail = true; this.send(); })
          }
        }.width('100%')
      }.padding(8).width('100%').borderRadius(16)
        .border({ width: 0.5, color: this.dark ? '#3B3B3E' : '#DFE1E5' })
        .backgroundColor(this.dark ? '#232324' : '#FFFFFF')
    }.padding({ left: 12, right: 12, top: 4, bottom: 8 }).height('100%').layoutWeight(1)
      .transition(TransitionEffect.OPACITY)
  }

  build() {
    Stack() {
    Column() {
      Row() {
        if (this.workspacePickerOpen) {
          NativeWorkspacePicker({ client: this.client, snapshot: this.workspaces, sessions: this.sessions, selectedId: this.workspaceId,
            onClose: (): void => { this.workspacePickerOpen = false; },
            onSelect: (id: string): void => { this.workspaceId = id; this.workspacePickerOpen = false; this.showSessions = true; },
            onChanged: (value: NativeWorkspaceSnapshot): void => { this.workspaces = value; } })
        } else if (this.newSessionOpen) { this.newSessionForm() }
        else {
        if (this.wide || this.showSessions) { this.sessionList() }
        if (!this.showSessions || this.wide) {
          if (this.selected) {
            this.conversation()
          }
          else {
            Column({ space: 16 }) {
              Text('开始你的任务').fontSize(24).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
              Text('选择一个会话，或新建会话连接 Harness。').fontSize(14).fontColor(this.dark ? '#CFD3D6' : '#61666B')
              Button('新建会话', { type: ButtonType.Normal }).height(44).borderRadius(12).fontSize(14)
                .backgroundColor(this.dark ? '#F9FAFB' : '#0F1115').fontColor(this.dark ? '#151517' : '#FFFFFF')
                .enabled(!this.loading).onClick(() => { this.openNewSession(); })
            }.layoutWeight(1).height('100%').justifyContent(FlexAlign.Center).padding(24)
          }
        }
        }
      }.width('100%').layoutWeight(1)
      if (this.archivedUndo) {
        Row() {
          Text('已归档会话').fontSize(12).layoutWeight(1)
          Button('撤销', { type: ButtonType.Normal }).height(36).fontSize(12).backgroundColor(Color.Transparent)
            .onClick(() => { const id = this.archivedUndo; this.archivedUndo = ''; this.client.operation(JSON.stringify({ operation: 'unarchive', sessionId: id })).then(() => { this.refreshSessionList(); }).catch((error: Error) => this.handleError(error)); })
          Button({ type: ButtonType.Normal }) { DSHIcon({ glyph: 'close-outline', glyphSize: 12, color: this.dark ? '#93969B' : '#8A8D91' }) }
            .height(36).width(32).backgroundColor(Color.Transparent).onClick(() => { this.archivedUndo = ''; })
        }.padding({ left: 12, right: 8 }).width('100%').backgroundColor(this.dark ? '#232324' : '#F5F6F7')
      }
      if (this.error) { Text(this.error).fontSize(12).padding(12).fontColor(this.dark ? '#FF9393' : '#C53030') }
    }.width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      .visibility(this.toolsOpen ? Visibility.Hidden : Visibility.Visible)
      .onAreaChange((_old: Area, area: Area) => { this.wide = Number(area.width) >= 760; this.groupHeight = Math.min(400, Number(area.height) / 2); this.navigationChanged(); })
    if (this.toolsOpen) {
      NativeSessionTools({ client: this.client, sessionId: this.toolsId,
        sessionTitle: this.sessions.find((item: NativeSession) => item.id === this.toolsId)?.title || this.title,
        onClose: (): void => { this.toolsOpen = false; },
        onRename: (title: string): void => { if (this.toolsId === this.selected) this.title = title; this.toolsOpen = false; this.refreshSessionList(); } })
    }
    }.width('100%').height('100%')
  }
  @Builder
  private newSessionForm() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        Button({ type: ButtonType.Normal }) { DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#F9FAFB' : '#17181B' }) }
          .width(36).height(36).backgroundColor(Color.Transparent).onClick(() => { this.newSessionOpen = false; })
        Text('新建会话').fontSize(18).fontWeight(FontWeight.Medium)
      }.width('100%')
      Scroll() {
        Column({ space: 8 }) {
          Text('工作区').fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91')
          Button('默认目录', { type: ButtonType.Normal }).width('100%').height(40).borderRadius(9)
            .backgroundColor(!this.newWorkspaceId ? this.dark ? '#353638' : '#EBEEF2' : Color.Transparent)
            .onClick(() => { this.newWorkspaceId = ''; })
          ForEach(this.workspaces.items, (workspace: NativeWorkspaceItem) => {
            Button(workspace.title, { type: ButtonType.Normal }).height(40).width('100%').borderRadius(9)
              .backgroundColor(this.newWorkspaceId === workspace.workspaceId ? this.dark ? '#353638' : '#EBEEF2' : Color.Transparent)
              .onClick(() => { this.newWorkspaceId = workspace.workspaceId; })
          }, (workspace: NativeWorkspaceItem) => workspace.workspaceId)
          if (!this.newWorkspaceId) { TextInput({ text: this.newCwd, placeholder: '工作目录' }).height(42).fontSize(13).onChange((value: string) => { this.newCwd = value; }) }
          TextInput({ text: this.newPreset, placeholder: '智能体预设 · 默认' }).height(42).fontSize(13).onChange((value: string) => { this.newPreset = value; })
          Button(this.loading ? '创建中…' : '创建会话', { type: ButtonType.Normal }).height(42).width('100%').borderRadius(10)
            .backgroundColor(this.dark ? '#679EFE' : '#3964FE').fontColor('#FFFFFF').enabled(!this.loading).onClick(() => { this.createSession(); })
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.padding(12).width('100%').height('100%').foregroundColor(this.dark ? '#F9FAFB' : '#17181B')
  }
}
