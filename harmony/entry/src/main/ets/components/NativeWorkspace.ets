import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NativeHarnessClient, NativeHttpError, NativeImageDraft } from '../services/NativeHarnessClient';
import { NativeFrame, NativeMessage, NativeSession, NativeSessionModel, NativePendingQuestion, NativeWorkspaceItem, NativeWorkspaceSnapshot, NativeWorkspaceRow, nativeWorkspaceRows, nativeToolsParent, nativeSessionDragOrder } from '../services/NativeSessionModel';
import { NativeListSource } from '../services/NativeListSource';
import { NativeExperience } from '../services/NativeExperience';
import { NativeTextContent } from './NativeTextContent';
import { NativeInteraction } from './NativeInteraction';
import { NativeSessionTools } from './NativeSessionTools';
import { NativeModelPicker } from './NativeModelPicker';
import { NativeMessageView } from './NativeMessageView';
import { DSHIcon } from './DSHIcon';
import { NativeProcessView } from './NativeProcessView';
import { nativeTranscript, nativePresentTranscript } from '../services/NativeTranscript';
import { NativeWorkspacePicker } from './NativeWorkspacePicker';
import { BackgroundMonitor } from '../services/BackgroundMonitor';
import { NativeActionMenu } from './NativeActionMenu';
import { NativeNavigationState, nativeSessionMenu, nativeCanGoBack, nativeForkTitle } from '../services/NativeNavigation';
import { NativeMenuItem } from '../services/NativeNavigation';
import { NativeMetadataCache } from '../services/NativeMetadataCache';
import { NativeTranscriptCache } from '../services/NativeTranscriptCache';

class NativeExportCapabilities { copyMarkdown: boolean = false; downloadLog: boolean = false; }
class NativeSessionInsertRequest {
  operation: string = 'sessionInsertBefore';
  workspaceId: string;
  sessionId: string;
  beforeSessionId?: string;
  constructor(workspaceId: string, sessionId: string) {
    this.workspaceId = workspaceId;
    this.sessionId = sessionId;
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
  onDestination: (destination: string) => void = (): void => {};
  @StorageLink('nativeBackRevision') @Watch('backToSessions') private backRevision: number = 0;
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeHostSettingsRevision') @Watch('preferencesChanged') private preferencesRevision: number = 0;
  @StorageLink('nativeModelRevision') @Watch('modelCaptionChanged') private modelRevision: number = 0;
  @StorageLink('nativeRefreshRevision') @Watch('reload') private refreshRevision: number = 0;
  @StorageLink('nativeCompatibilityActive') @Watch('activityChanged') private fallbackActive: boolean = false;
  @StorageLink('nativeAppActive') @Watch('activityChanged') private active: boolean = true;
  @StorageLink('nativeBackgroundMonitor') @Watch('activityChanged') private backgroundMonitor: boolean = false;
  @StorageLink('requestedSession') @Watch('openRequested') private requestedSession: string = '';
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @State @Watch('sessionsChanged') private sessions: NativeSession[] = [];
  @State private continued: NativeFrame[] = [];
  @State private interactions: NativeFrame[] = [];
  @State private images: NativeImageDraft[] = [];
  @State private attaching: boolean = false;
  @State @Watch('navigationChanged') private toolsOpen: boolean = false;
  @State private toolsId: string = '';
  @State @Watch('navigationChanged') private modelPickerOpen: boolean = false;
  @State @Watch('navigationChanged') private menuId: string = '';
  @State private menuTarget: string = '';
  @State @Watch('navigationChanged') private utilityOpen: boolean = false;
  @State private copying: boolean = false;
  @State private modelCaption: string = '模型';
  @State private groupHeight: number = 400;
  @State private downloading: boolean = false;
  @State private utilityKnown: boolean = false;
  @State private exportCapabilities: NativeExportCapabilities = new NativeExportCapabilities();
  @State private menuBusy: boolean = false;
  @State private archivedUndo: string = '';
  @State private steer: boolean = false;
  @State @Watch('navigationChanged') private newSessionOpen: boolean = false;
  @State @Watch('navigationChanged') private workspacePickerOpen: boolean = false;
  @State @Watch('sessionsChanged') private workspaces: NativeWorkspaceSnapshot = new NativeWorkspaceSnapshot();
  @State @Watch('sessionsChanged') private workspaceId: string = '';
  @State @Watch('sessionsChanged') private query: string = '';
  @State private searchOpen: boolean = false;
  @State private newWorkspaceId: string = '';
  @State private newCwd: string = '';
  @State private newPreset: string = '';
  @State private selected: string = '';
  @State private title: string = '工作空间';
  @State private draft: string = '';
  @State @Watch('navigationChanged') private showSessions: boolean = false;
  @State @Watch('navigationChanged') private wide: boolean = false;
  @State private windowWidth: number = 0;
  @State private loading: boolean = true;
  @State private sending: boolean = false;
  @State private connectionPhase: string = 'idle';
  @State private running: boolean = false;
  @State private waiting: boolean = false;
  @State private uncertain: boolean = false;
  private connectionNotified: boolean = false;
  @State private error: string = '';
  @State private paging: boolean = false;
  @State private hasMore: boolean = false;
  @State private visibleSessionCount: number = 0;
  @State private collapsedGroups: string[] = [];
  @State private workspaceLoading: boolean = false;
  @State private workspaceError: string = '';
  @State private manualOrder: boolean = false;
  @State private dragSessionId: string = '';
  @State private dropSessionId: string = '';
  @State private streamText: string = '';
  @State private streamReasoning: string = '';
  @State private footerCopiedId: string = '';
  private sessionSource: NativeListSource<NativeWorkspaceRow> = new NativeListSource<NativeWorkspaceRow>();
  private source: NativeListSource<NativeMessage> = new NativeListSource<NativeMessage>();
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
  private widgetEventTimer: number = -1;
  private backgroundTimer: number = -1;
  private preloadTimer: number = -1;
  private backgroundActive: boolean = false;
  private backgroundBusy: boolean = false;
  private backgroundStates: Map<string, string> = new Map<string, string>();
  private openTurns: Set<string> = new Set<string>();
  private visibleRows: NativeMessage[] = [];
  private firstVisible: number = 0;
  private userHasScrolled: boolean = false;
  private prefetchQueue: number = 0;
  private prefetching: boolean = false;
  private selectionGeneration: number = 0;
  private cacheTimer: number = -1;
  private sessionRowRects: Map<string, number[]> = new Map<string, number[]>();

  private preferencesChanged(): void { this.steer = this.client.hostSettings.chat().busyEnter === 'steer'; this.renderTranscript(); }
  private modelCaptionChanged(): void { this.modelCaption = this.client.modelDirectory.caption(this.selected); }

  private navigationChanged(): void {
    const state = new NativeNavigationState();
    state.wide = this.wide; state.drawerOpen = this.showSessions;
    state.drawerPage = this.searchOpen ? 'search' : 'primary';
    state.picker = this.workspacePickerOpen;
    state.create = this.newSessionOpen; state.tools = this.toolsOpen;
    state.menu = !!this.menuId || this.utilityOpen || this.modelPickerOpen;
    AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', nativeCanGoBack(state));
  }

  private sessionsChanged(): void {
    const visible = nativeWorkspaceRows(this.sessions, this.workspaces, this.workspaceId, this.query, this.client.models,
      this.selected, this.collapsedGroups, this.manualOrder);
    this.visibleSessionCount = visible.filter((row: NativeWorkspaceRow) => !row.group).length;
    this.sessionSource.set(visible, (row: NativeWorkspaceRow): string => row.key);
  }
  aboutToAppear(): void { this.mounted = true; this.reload(); }
  aboutToDisappear(): void {
    this.mounted = false; this.generation++; this.client.pause();
    clearTimeout(this.paintTimer); clearTimeout(this.reconnectTimer); clearTimeout(this.widgetTimer);
    clearTimeout(this.widgetEventTimer);
    clearTimeout(this.backgroundTimer); clearTimeout(this.preloadTimer);
    clearTimeout(this.cacheTimer);
    this.persistCache();
    this.stopBackground();
    AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', false);
  }
  private async reload(): Promise<void> {
    const generation = ++this.generation;
    await this.client.prepareCacheKey();
    const cached = NativeMetadataCache.read(this.context, this.client.cacheKey());
    if (cached.sessions.length) {
      this.sessions = cached.sessions;
      if (cached.workspaces) { this.workspaces = cached.workspaces; this.manualOrder = true; }
      this.loading = false;
      this.sessionsChanged();
      // Paint the remembered conversation from the encrypted cache before the
      // navigation refresh or live socket becomes available.
      const cachedRequested = this.requestedSession ||
        await NativeTranscriptCache.loadRoute(this.context, this.client.cacheKey()) ||
        NativeMetadataCache.readLastSession(this.context, this.client.cacheKey());
      if (cachedRequested && !this.selected) {
        const available = this.sessions.some((item: NativeSession): boolean =>
          item.id === cachedRequested && item.blank !== true && item.origin !== 'subagent' &&
          !this.workspaces.archivedSessionIds.includes(item.id));
        if (available) {
          this.requestedSession = '';
          this.select(cachedRequested);
        }
      }
      if (!this.selected) this.animatePane(() => { this.showSessions = true; });
    } else this.loading = true;
    this.error = '';
    try {
      const statePending = this.client.state();
      const sessionsPending = this.client.sessions();
      const workspacesPending = this.client.workspaces();
      sessionsPending.catch(() => {});
      workspacesPending.catch(() => {});
      const state = await statePending;
      if (!this.mounted || generation !== this.generation) return;
      if (!state.authenticated) { this.onLogin(); return; }
      const value = await sessionsPending;
      const nextWorkspaces = await workspacesPending;
      if (!this.mounted || generation !== this.generation) return;
      if (value.protocol !== 2) throw new Error('请升级网关或使用兼容模式');
      this.sessions = value.items;
      if (nextWorkspaces.available) {
        this.workspaces = nextWorkspaces;
        this.manualOrder = true;
      }
      this.client.hostSettings.refresh().catch(() => {});
      NativeMetadataCache.save(this.context, this.client.cacheKey(), this.sessions,
        nextWorkspaces.available ? nextWorkspaces : this.workspaces);
      this.preloadMetadata();
      this.updateWidget();
      const requested = this.requestedSession || await NativeTranscriptCache.loadRoute(this.context, this.client.cacheKey()) ||
        NativeMetadataCache.readLastSession(this.context, this.client.cacheKey()) || this.client.selectedId;
      if (requested) {
        this.requestedSession = '';
        const available = value.items.some((item: NativeSession): boolean =>
          item.id === requested && item.blank !== true && item.origin !== 'subagent' &&
          !nextWorkspaces.archivedSessionIds.includes(item.id));
        if (!available) NativeMetadataCache.forgetSession(this.context, this.client.cacheKey());
        if (available && requested === this.selected) {
          const session = this.sessions.find((item: NativeSession) => item.id === requested);
          if (session) this.title = session.title.trim() || '未命名会话';
          if (this.connectionPhase !== 'opening' && this.connectionPhase !== 'syncing' &&
            this.connectionPhase !== 'live') this.follow();
        } else if (available) this.select(requested);
        else this.animatePane(() => { this.showSessions = true; });
      } else this.animatePane(() => { this.showSessions = true; });
    } catch (error) {
      if (!this.sessions.length) this.handleError(error as Error);
      if (this.sessions.length && !this.selected) this.animatePane(() => { this.showSessions = true; });
      if (!(error instanceof NativeHttpError && error.status === 401)) {
        this.connectionPhase = 'retrying';
        if (!this.selected) this.animatePane(() => { this.showSessions = true; });
        this.scheduleReconnect('');
      }
    }
    finally { if (this.mounted && generation === this.generation) this.loading = false; }
  }
  private preloadMetadata(): void {
    clearTimeout(this.preloadTimer);
    const ids = this.sessions.filter((session: NativeSession): boolean => session.blank !== true)
      .slice(0, 3).map((session: NativeSession): string => session.id);
    const generation = this.generation;
    this.preloadTimer = setTimeout((): void => {
      const next = (index: number): void => {
        if (!this.mounted || index >= ids.length) return;
        const id = ids[index];
        this.client.modelDirectory.load(id).catch(() => {}).finally((): void => {
          if (!this.mounted || generation !== this.generation) return;
          if (this.client.models.has(id)) { next(index + 1); return; }
          NativeTranscriptCache.loadSession(this.context, this.client.cacheKey(), id)
            .then((cached): void => {
              if (!this.mounted || generation !== this.generation || !cached ||
                !cached.messages.length || this.client.models.has(id)) return;
              const model = new NativeSessionModel();
              model.restore(cached);
              this.client.models.set(id, model);
            }).catch((): void => {}).finally((): void => {
              if (this.mounted && generation === this.generation) next(index + 1);
            });
        });
      };
      next(0);
    }, 160);
  }
  private handleError(error: Error): void {
    if (!this.mounted) return;
    if (error instanceof NativeHttpError && error.status === 401) { this.onLogin(); return; }
    this.error = error.message || '连接失败，请刷新或使用兼容模式';
  }
  private activityChanged(): void {
    clearTimeout(this.reconnectTimer); clearTimeout(this.widgetTimer);
    clearTimeout(this.widgetEventTimer);
    if (!this.active || this.fallbackActive) {
      this.persistCache();
      this.interactions = []; this.client.pause(); this.connectionPhase = 'paused';
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
  private mobileDrawerWidth(): number {
    return Math.max(240, Math.min(380, this.windowWidth * 0.86, this.windowWidth - 48));
  }
  private openDrawer(): void {
    this.animatePane(() => { this.showSessions = true; });
    this.navigationChanged();
  }
  private closeDrawer(): void {
    this.animatePane(() => { this.showSessions = false; });
    this.navigationChanged();
  }
  private backToSessions(): void {
    if (this.menuId || this.utilityOpen) { this.menuId = ''; this.utilityOpen = false; return; }
    if (this.modelPickerOpen) { this.modelPickerOpen = false; return; }
    if (this.workspacePickerOpen) { this.workspacePickerOpen = false; return; }
    if (this.newSessionOpen) { this.newSessionOpen = false; return; }
    if (this.toolsOpen) {
      const parent = nativeToolsParent(AppStorage.get<string>('nativeSessionToolsPage') || 'root');
      if (parent) AppStorage.setOrCreate<string>('nativeSessionToolsPage', parent);
      else this.toolsOpen = false;
      return;
    }
    if (this.showSessions) this.closeDrawer();
    this.sessionsChanged();
    this.navigationChanged();
  }
  private openTools(page: string, id: string = this.selected): void {
    this.toolsId = id; AppStorage.setOrCreate<string>('nativeSessionToolsPage', page); this.toolsOpen = true;
  }
  private async refreshSessionList(): Promise<void> {
    const rows = await this.client.sessions();
    if (this.mounted) {
      this.sessions = rows.items;
      await this.refreshWorkspaces();
      NativeMetadataCache.save(this.context, this.client.cacheKey(), this.sessions,
        this.workspaces.available ? this.workspaces : null);
    }
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
        if (this.selected === id) {
          this.client.pause(); this.selected = ''; this.client.selectedId = ''; this.showSessions = true;
          NativeMetadataCache.forgetSession(this.context, this.client.cacheKey());
          NativeTranscriptCache.forgetSession(this.context, this.client.cacheKey(), id).catch(() => {});
        }
      }
      await this.refreshSessionList();
    } catch (error) { this.handleError(error as Error); }
    finally { this.menuBusy = false; }
  }
  private sessionWorkspace(id: string): NativeWorkspaceItem | undefined {
    return this.workspaces.items.find((workspace: NativeWorkspaceItem) => workspace.sessionIds.includes(id));
  }
  private beginSessionDrag(id: string): CustomBuilder | DragItemInfo {
    const session = this.sessions.find((item: NativeSession) => item.id === id);
    if (session && session.blank !== true) this.dragSessionId = id;
    return this.sessionDragBuilder;
  }
  private async dropSession(target: string, event: DragEvent): Promise<void> {
    const sourceId = this.dragSessionId;
    this.dragSessionId = ''; this.dropSessionId = '';
    if (!sourceId || sourceId === target) return;
    const source = this.sessions.find((item: NativeSession) => item.id === sourceId);
    const targetSession = this.sessions.find((item: NativeSession) => item.id === target);
    const workspace = this.sessionWorkspace(sourceId);
    const targetWorkspace = this.sessionWorkspace(target);
    if (!source || source.blank === true || !targetSession || targetSession.blank === true ||
        !workspace || !targetWorkspace || workspace.workspaceId !== targetWorkspace.workspaceId) {
      event.setResult(DragResult.DROP_DISABLED);
      return;
    }
    const sourcePinned = this.workspaces.pinnedSessionIds.includes(sourceId);
    const targetPinned = this.workspaces.pinnedSessionIds.includes(target);
    if (sourcePinned !== targetPinned) {
      event.setResult(DragResult.DROP_DISABLED);
      return;
    }
    event.setResult(DragResult.DROP_ENABLED);
    const rect = this.sessionRowRects.get(target) || [];
    const after = rect.length >= 2 && event.getWindowY() > rect[0] + rect[1] / 2;
    const order = nativeSessionDragOrder(workspace.sessionIds, sourceId, target, after,
      sourcePinned, targetPinned);
    if (!order) return;
    const sourceIndex = order.indexOf(sourceId);
    const beforeSessionId = sourceIndex >= 0 ? order[sourceIndex + 1] || '' : '';
    const previous = this.workspaces;
    const next = new NativeWorkspaceSnapshot();
    next.available = previous.available;
    next.archivedSessionIds = previous.archivedSessionIds.slice();
    next.pinnedSessionIds = previous.pinnedSessionIds.slice();
    next.items = previous.items.map((item: NativeWorkspaceItem): NativeWorkspaceItem => {
      const row = new NativeWorkspaceItem();
      row.workspaceId = item.workspaceId; row.path = item.path; row.title = item.title;
      row.sessionIds = item.workspaceId === workspace.workspaceId ? order : item.sessionIds.slice();
      return row;
    });
    const update = (): void => { this.manualOrder = true; this.workspaces = next; this.sessionsChanged(); };
    if (NativeExperience.reducedMotion()) update();
    else this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, update);
    try {
      const body = new NativeSessionInsertRequest(workspace.workspaceId, sourceId);
      if (beforeSessionId) body.beforeSessionId = beforeSessionId;
      await this.client.operation(JSON.stringify(body));
      await this.refreshSessionList();
    } catch (error) {
      this.workspaces = previous; this.sessionsChanged(); this.handleError(error as Error);
      this.getUIContext().getPromptAction().showToast({ message: '排序未保存，请重试', duration: 1500 });
    }
  }
  @Builder
  private sessionDragBuilder() {
    Row({ space: 7 }) {
      DSHIcon({ glyph: 'new-chat-outline', glyphSize: 14, color: this.dark ? '#F9FAFB' : '#17181B' })
      Text(this.sessions.find((item: NativeSession) => item.id === this.dragSessionId)?.title || '会话')
        .fontSize(13).maxLines(1).fontColor(this.dark ? '#F9FAFB' : '#17181B')
    }.padding({ left: 12, right: 12, top: 9, bottom: 9 }).borderRadius(10)
      .backgroundColor(this.dark ? '#353638' : '#FFFFFF')
      .border({ width: 0.5, color: this.dark ? '#4A4B4F' : '#D8DADF' })
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
    NativeActionMenu({ items: this.utilityItems(), onSelect: (id: string): void => { if (id === 'copy') this.copyMarkdown(); else if (id === 'download') this.downloadLog(); } })
  }
  @Builder
  private modelPicker() {
    NativeModelPicker({ client: this.client, sessionId: this.selected, currentCaption: this.modelCaption,
      onClose: (): void => { this.modelPickerOpen = false; } })
  }
  private utilityItems(): NativeMenuItem[] {
    const rows: NativeMenuItem[] = [];
    if (this.utilityKnown && this.exportCapabilities.copyMarkdown) rows.push({ id: 'copy', title: '复制 Markdown', icon: 'copy-outline', disabled: this.copying, danger: false, separator: false });
    if (this.utilityKnown && this.exportCapabilities.downloadLog) rows.push({ id: 'download', title: '下载日志', icon: 'download-outline', disabled: this.downloading, danger: false, separator: false });
    if (!rows.length) rows.push({ id: 'none', title: this.utilityKnown ? '此服务未提供导出' : '正在加载…', icon: 'download-outline', disabled: true, danger: false, separator: false });
    return rows;
  }
  private async openUtilities(): Promise<void> {
    this.modelPickerOpen = false;
    this.utilityOpen = !this.utilityOpen; if (!this.utilityOpen) return;
    const id = this.selected; this.utilityKnown = false;
    try {
      const value = JSON.parse(await this.client.operation(JSON.stringify({ operation: 'capabilities', sessionId: id }))) as NativeExportCapabilities;
      if (this.mounted && this.selected === id) this.exportCapabilities = value;
    } catch (_) { if (this.mounted && this.selected === id) this.exportCapabilities = new NativeExportCapabilities(); }
    finally { if (this.mounted && this.selected === id) this.utilityKnown = true; }
  }
  private async refreshWorkspaces(): Promise<void> {
    if (this.workspaceLoading) return;
    this.workspaceLoading = true; this.workspaceError = '';
    try {
      const value = await this.client.workspaces();
      if (!value.available) throw new Error('Workspace unavailable');
      if (this.mounted) { this.workspaces = value; this.manualOrder = true; }
    } catch (error) {
      if (this.mounted) {
        this.workspaceError = '工作区加载失败';
        if (error instanceof NativeHttpError && error.status === 401) this.onLogin();
      }
    } finally { if (this.mounted) this.workspaceLoading = false; }
  }
  private openNewSession(): void {
    if (this.workspaceId && this.workspaceId !== 'other') {
      this.createQuickSession(this.workspaceId);
      return;
    }
    if (this.workspaces.items.length === 1) {
      this.createQuickSession(this.workspaces.items[0].workspaceId);
      return;
    }
    this.workspacePickerOpen = true;
  }
  private async createQuickSession(workspaceId: string): Promise<void> {
    if (this.loading || !workspaceId) return;
    this.loading = true; this.error = '';
    try {
      const workspace = this.workspaces.items.find((item: NativeWorkspaceItem) =>
        item.workspaceId === workspaceId);
      const reusable = workspace ? this.sessions.find((item: NativeSession) =>
        item.blank === true && workspace.sessionIds.includes(item.id) &&
        !this.workspaces.archivedSessionIds.includes(item.id)) : undefined;
      const id = await this.client.create('', '', workspaceId, reusable?.id || '');
      if (!this.mounted) return;
      const value = await this.client.sessions();
      if (!this.mounted) return;
      this.sessions = value.items;
      const refreshed = await this.client.workspaces();
      if (this.mounted && refreshed.available) this.workspaces = refreshed;
      this.workspaceId = workspaceId;
      this.select(id);
    } catch (error) { this.handleError(error as Error); }
    finally { if (this.mounted) this.loading = false; }
  }
  private async updateWidget(): Promise<void> {
    clearTimeout(this.widgetTimer);
    if (!this.mounted || !this.active || this.fallbackActive) return;
    let delay = 60000;
    try {
      const value = await this.client.request('/pocket/api/overview');
      try {
        const overview = JSON.parse(value) as Record<string, Object>;
        const running = Number(overview.running || 0);
        const waiting = Number(overview.waiting || 0);
        if (running + waiting > 0) delay = 30000;
      } catch (_) {}
      if (this.mounted && this.active && !this.fallbackActive) {
        this.rememberBackgroundStates(value);
        await this.onSnapshot(value);
      }
    } catch (_) {}
    finally {
      if (this.mounted && this.active && !this.fallbackActive) {
        this.widgetTimer = setTimeout(() => { this.updateWidget(); }, delay);
      }
    }
  }
  private scheduleWidgetUpdate(): void {
    clearTimeout(this.widgetEventTimer);
    this.widgetEventTimer = setTimeout((): void => {
      this.widgetEventTimer = -1;
      this.updateWidget();
    }, 1200);
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
    const id = this.requestedSession; this.requestedSession = '';
    this.openRequestedSession(id);
  }
  private async openRequestedSession(id: string): Promise<void> {
    const valid = (session: NativeSession): boolean =>
      session.id === id && session.blank !== true && session.origin !== 'subagent' &&
      !this.workspaces.archivedSessionIds.includes(id);
    if (!this.sessions.some(valid)) {
      try { await this.refreshSessionList(); } catch (_) {}
    }
    if (!this.mounted || !this.sessions.some(valid)) {
      if (this.mounted) {
        this.workspaceError = '会话不可用';
        this.animatePane(() => { this.showSessions = true; });
        this.navigationChanged();
      }
      return;
    }
    this.select(id);
  }
  private select(id: string): void {
    if (!id) return;
    const selection = ++this.selectionGeneration;
    this.paging = false;
    this.prefetchQueue = 0;
    if (this.selected) {
      const previousId = this.selected;
      this.client.models.set(previousId, this.model);
      NativeTranscriptCache.saveSession(this.context, this.client.cacheKey(), previousId, this.model)
        .catch((): void => {});
    }
    this.client.drafts.set(this.selected, this.draft);
    this.continued = []; this.interactions = []; this.toolsOpen = false; this.modelPickerOpen = false; this.client.selectedId = id;
    const session = this.sessions.find((item: NativeSession) => item.id === id);
    this.title = session ? session.title.trim() || '未命名会话' : '会话';
    this.draft = this.client.drafts.get(id) || '';
    this.images = this.client.images.get(id) || [];
    this.uncertain = this.client.uncertain.has(id);
    this.connectionNotified = false;
    this.animatePane(() => { this.selected = id; this.showSessions = false; }); this.followTail = true;
    NativeMetadataCache.rememberSession(this.context, this.client.cacheKey(), id);
    NativeTranscriptCache.saveRoute(this.context, this.client.cacheKey(), id).catch(() => {});
    this.navigationChanged();
    this.model = this.client.models.get(id) || new NativeSessionModel();
    this.client.models.set(id, this.model);
    this.previousRows = this.model.messages;
    this.renderTranscript();
    this.streamText = ''; this.streamReasoning = '';
    this.running = false; this.waiting = false; this.retries = 0;
    this.connectionPhase = 'syncing'; this.userHasScrolled = false;
    if (this.model.messages.length) {
      this.paint();
      this.follow();
    } else {
      this.restoreAndFollow(id, selection);
    }
    this.client.modelDirectory.load(id).catch(() => {});
  }
  private async restoreAndFollow(id: string, selection: number): Promise<void> {
    try {
      const cached = await NativeTranscriptCache.loadSession(this.context, this.client.cacheKey(), id);
      if (!this.mounted || selection !== this.selectionGeneration || this.selected !== id) return;
      if (cached !== null && cached.messages.length) {
        this.model.restore(cached);
        this.followTail = true;
        this.paint();
      }
    } catch (_) {}
    if (this.mounted && selection === this.selectionGeneration && this.selected === id) {
      this.follow();
    }
  }
  private follow(): void {
    if (!this.mounted || !this.active || this.fallbackActive || !this.selected) return;
    clearTimeout(this.reconnectTimer);
    const id = this.selected;
    this.connectionPhase = 'syncing';
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
        this.notifyConnectionFailure(id);
        this.reconnect(id);
        return;
      }
      const wasActive = this.running || this.waiting;
      this.model.apply(frame);
      if (frame.type === 'state' && wasActive !== (this.model.running || this.model.waiting)) {
        this.scheduleWidgetUpdate();
      }
      this.scheduleCache();
      if (frame.type === 'snapshot') {
        this.connectionPhase = 'live'; this.error = ''; this.retries = 0;
        this.connectionNotified = false;
        // The live snapshot starts at 24 records. Three 60-record pages bring
        // the normal working set above the 180-record preload floor.
        setTimeout((): void => { this.queuePrefetch(3); }, 80);
      }
      if (this.paintTimer < 0) this.paintTimer = setTimeout(() => { this.paintTimer = -1; this.paint(); }, 40);
    }, (reason: string): void => {
      console.error('DSH Harmony live socket ended: ' + reason);
      this.reconnect(id);
    }).catch((): void => { this.scheduleReconnect(id); });
  }
  private async reconnect(id: string): Promise<void> {
    if (!this.mounted || !this.active || this.fallbackActive || this.selected !== id) return;
    this.notifyConnectionFailure(id);
    this.connectionPhase = 'syncing';
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
    this.notifyConnectionFailure(id);
    const exposeFailure = this.connectionPhase === 'live' || this.retries > 0;
    if (exposeFailure) this.connectionPhase = 'retrying';
    else this.connectionPhase = 'syncing';
    this.error = '';
    this.retries++;
    const delay = Math.min(30000, 1000 * Math.pow(2, Math.min(this.retries, 5)));
    this.reconnectTimer = setTimeout(() => { if (id) this.follow(); else this.reload(); }, delay);
  }
  private notifyConnectionFailure(id: string): void {
    if (!id || this.connectionPhase !== 'live' || this.connectionNotified) return;
    this.connectionNotified = true;
    const title = this.sessions.find((item: NativeSession): boolean => item.id === id)?.title ||
      this.title || 'DSH Harmony';
    this.onLocalNotification(id, title, 'connection').catch(() => {});
  }
  private paint(): void {
    if (!this.mounted) return;
    this.previousRows = this.model.messages; this.renderTranscript();
    this.running = this.model.running; this.waiting = this.model.waiting; this.hasMore = this.model.hasMore;
    this.streamText = this.model.streamText; this.streamReasoning = this.model.streamReasoning;
    if (this.followTail) setTimeout(() => { if (this.mounted) this.scroller.scrollEdge(Edge.Bottom); }, 0);
  }
  private renderTranscript(): void {
    const rows = nativeTranscript(this.model.messages, this.model.running, this.model.streamTools, this.model.streamReasoning, this.model.streamText);
    const visible = nativePresentTranscript(rows, this.client.hostSettings.chat(), this.model.turnDisclosure, this.model.collapseThrough);
    this.openTurns = new Set<string>(visible.filter((row: NativeMessage) => row.role === 'process').map((row: NativeMessage) => row.turnKey));
    this.visibleRows = visible;
    this.source.set(visible, (row: NativeMessage): string => row.id);
  }
  private copyFooter(text: string, id: string): void {
    if (!text) return;
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
      .then((): void => {
        this.footerCopiedId = id;
        setTimeout((): void => {
          if (this.footerCopiedId === id) this.footerCopiedId = '';
        }, 1000);
      }).catch((): void => {});
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
  private queuePrefetch(pages: number): void {
    this.prefetchQueue = Math.min(4, Math.max(this.prefetchQueue, pages));
    this.pumpPrefetch();
  }
  private scheduleCache(): void {
    clearTimeout(this.cacheTimer);
    this.cacheTimer = setTimeout((): void => {
      this.cacheTimer = -1;
      this.persistCache();
    }, 500);
  }
  private persistCache(): void {
    const id = this.selected;
    if (!id || !this.model.messages.length) return;
    const scope = this.client.cacheKey();
    NativeTranscriptCache.saveSession(this.context, scope, id, this.model)
      .then((): void => {
        const protectedSessions: string[] = Array.from(this.client.drafts.keys())
          .concat(Array.from(this.client.uncertain.values()));
        NativeTranscriptCache.trimToQuota(this.context, scope, id, protectedSessions).catch(() => {});
      }).catch(() => {});
  }
  private async pumpPrefetch(): Promise<void> {
    if (this.prefetching || this.prefetchQueue <= 0 || !this.hasMore || this.connectionPhase !== 'live') return;
    const id = this.selected;
    const generation = this.selectionGeneration;
    this.prefetching = true;
    try {
      while (this.mounted && this.selected === id && this.selectionGeneration === generation &&
        this.prefetchQueue > 0 && this.hasMore && this.connectionPhase === 'live') {
        this.prefetchQueue--;
        await this.older(true);
        if (this.selected !== id || this.selectionGeneration !== generation) break;
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 32); });
      }
    } finally {
      this.prefetching = false;
      if (this.mounted && this.prefetchQueue > 0 && this.hasMore && this.connectionPhase === 'live') {
        setTimeout((): void => { this.pumpPrefetch(); }, 120);
      }
    }
  }
  private async older(prefetch: boolean = false): Promise<void> {
    if (this.paging || !this.hasMore || this.model.historyBefore < 0) return;
    const id = this.selected;
    const generation = this.selectionGeneration;
    const scope = this.client.cacheKey();
    const historyBefore = this.model.historyBefore;
    const historyCut = this.model.historyCut;
    this.paging = true;
    if (!prefetch) this.followTail = false;
    try {
      const page = await this.client.page(id, historyBefore, historyCut);
      if (this.selected !== id || this.selectionGeneration !== generation || !this.mounted) return;
      const offset = this.hasMore ? 1 : 0;
      let anchorIndex = Math.max(0, this.firstVisible - offset);
      while (anchorIndex < this.visibleRows.length - 1 && this.visibleRows[anchorIndex].role === 'turn-control') anchorIndex++;
      const anchor = this.visibleRows[anchorIndex]?.id || '';
      let top = 0;
      try {
        top = this.scroller.getItemRect(anchorIndex + offset).y;
      } catch (_) {
        // LazyForEach can leave the anchor unmeasured during a fast fling.
        // Prepend the page without forcing a scroll correction in that case.
      }
      this.model.prepend(page); this.paint();
      NativeTranscriptCache.saveSession(this.context, scope, id, this.model).catch(() => {});
      const next = this.visibleRows.findIndex((row: NativeMessage) => row.id === anchor);
      if (next >= 0 && top !== 0) setTimeout(() => { if (!this.mounted || this.selected !== id) return;
        try {
          this.scroller.scrollToIndex(next + (this.hasMore ? 1 : 0), false, ScrollAlign.START);
          this.scroller.scrollBy(0, -top);
        } catch (_) {}
      }, 0);
    } catch (error) {
      if (this.selected === id && this.selectionGeneration === generation) this.handleError(error as Error);
    } finally {
      if (this.selectionGeneration === generation) this.paging = false;
    }
  }

  @Builder
  private sessionRow(item: NativeSession) {
    Row({ space: 8 }) {
      Text(item.title.trim() || '未命名会话').fontSize(14).layoutWeight(1).wordBreak(WordBreak.BREAK_WORD)
        .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
      if (item.running) { Text('运行中').fontSize(10).fontColor(this.dark ? '#C7D8FF' : '#3B5B9A') }
      if (this.workspaces.pinnedSessionIds.includes(item.id)) {
        DSHIcon({ glyph: 'pin-fill', glyphSize: 12, color: this.dark ? '#93969B' : '#8A8D91' })
      }
      if (item.blank !== true) {
        Button({ type: ButtonType.Normal }) { DSHIcon({ glyph: 'ellipsis-outline', color: this.menuId === item.id ? this.dark ? '#F9FAFB' : '#17181B' : this.dark ? '#93969B' : '#8A8D91' }) }
          .width(34).height(34).padding(6).borderRadius(8)
          .backgroundColor(this.menuId === item.id ? this.dark ? '#45464B' : '#DBDEE4' : Color.Transparent).enabled(!this.menuBusy)
          .accessibilityText(item.title + '，会话操作').onClick(() => { this.menuTarget = item.id; this.menuId = item.id; })
          .bindPopup(this.menuId === item.id, { builder: this.sessionMenu, placement: Placement.BottomRight,
            enableArrow: false, targetSpace: 4, radius: 16, mask: true,
            popupColor: this.dark ? '#37383C' : '#F8F9FA', backgroundBlurStyle: BlurStyle.NONE,
            onStateChange: (event): void => { if (!event.isVisible && this.menuId === item.id) this.menuId = ''; } })
      }
    }.padding({ left: 10, right: 4, top: 5, bottom: 5 }).width('100%').constraintSize({ minHeight: 44 }).borderRadius(10)
      .backgroundColor(this.selected === item.id ? this.dark ? '#2C2C2E' : '#EBEEF2' : Color.Transparent)
      .border({ width: this.dropSessionId === item.id ? 1 : 0,
        color: this.dropSessionId === item.id ? this.dark ? '#8AB4FF' : '#3964FE' : Color.Transparent })
      .opacity(this.dragSessionId === item.id ? 0.7 : 1)
      .draggable(item.blank !== true)
      .onDragStart((): CustomBuilder | DragItemInfo => this.beginSessionDrag(item.id))
      .onDragEnter((): void => { this.dropSessionId = item.id; })
      .onDragLeave((): void => { if (this.dropSessionId === item.id) this.dropSessionId = ''; })
      .onDrop((event: DragEvent): void => { this.dropSession(item.id, event); })
      .onAreaChange((_old: Area, area: Area): void => {
        this.sessionRowRects.set(item.id,
          [Number(area.globalPosition.y), Number(area.height)]);
      })
  }

  @Builder
  private sessionList() {
    Column({ space: 6 }) {
      Row({ space: 4 }) {
        Text('DSH Harmony').fontSize(21).fontWeight(FontWeight.Bold).layoutWeight(1)
          .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'search-outline', glyphSize: 17, color: this.dark ? '#CFD3D6' : '#61666B' })
        }.width(40).height(40).borderRadius(12).backgroundColor(Color.Transparent)
          .accessibilityText(this.searchOpen ? '关闭搜索' : '搜索工作区和会话')
          .onClick(() => {
            if (this.searchOpen) this.query = '';
            this.searchOpen = !this.searchOpen;
          })
        if (!this.wide) {
          Button({ type: ButtonType.Normal }) {
            DSHIcon({ glyph: 'close-outline', glyphSize: 16, color: this.dark ? '#CFD3D6' : '#61666B' })
          }.width(40).height(40).borderRadius(12).backgroundColor(Color.Transparent)
            .accessibilityText('关闭侧边栏').onClick(() => { this.closeDrawer(); })
        }
      }.width('100%').height(52)
      Button({ type: ButtonType.Normal }) {
        Row({ space: 9 }) {
          DSHIcon({ glyph: 'new-chat-outline', glyphSize: 17, color: this.dark ? '#F9FAFB' : '#0F1115' })
          Text('新会话').fontSize(14).fontWeight(FontWeight.Medium)
          Blank()
        }.width('100%').padding({ left: 10, right: 10 })
      }.width('100%').height(42).borderRadius(12).backgroundColor(this.dark ? '#353638' : '#EBEEF2')
        .fontColor(this.dark ? '#F9FAFB' : '#0F1115').enabled(!this.loading)
        .onClick(() => { this.openNewSession(); })
      Column({ space: 1 }) {
        Row({ space: 10 }) {
          DSHIcon({ glyph: 'code-outline', glyphSize: 17, color: this.dark ? '#CFD3D6' : '#61666B' })
          Text('插件').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F1F1F2' : '#25262A')
        }.width('100%').height(40).padding({ left: 10, right: 10 })
          .onClick(() => { this.closeDrawer(); this.onDestination('plugins'); })
        Row({ space: 10 }) {
          DSHIcon({ glyph: 'plan-outline', glyphSize: 17, color: this.dark ? '#CFD3D6' : '#61666B' })
          Text('自动化任务').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F1F1F2' : '#25262A')
        }.width('100%').height(40).padding({ left: 10, right: 10 })
          .onClick(() => { this.closeDrawer(); this.onDestination('automation'); })
        Row({ space: 10 }) {
          DSHIcon({ glyph: 'ellipsis-outline', glyphSize: 17, color: this.dark ? '#CFD3D6' : '#61666B' })
          Text('更多').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F1F1F2' : '#25262A')
        }.width('100%').height(40).padding({ left: 10, right: 10 })
          .onClick(() => { this.closeDrawer(); this.onDestination('more'); })
      }.width('100%')
      if (this.searchOpen) {
        TextInput({ text: this.query, placeholder: '搜索工作区和会话' }).height(36).fontSize(13).borderRadius(10)
          .placeholderColor(this.dark ? '#93969B' : '#8A8D91')
          .backgroundColor(this.dark ? '#232324' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onChange((value: string) => { this.query = value; })
      }
      Row({ space: 6 }) {
        Text('工作区').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#B5B8BD' : '#61666B')
        Blank()
        Button({ type: ButtonType.Normal }) {
          Row({ space: 5 }) {
            DSHIcon({ glyph: 'browse-outline', glyphSize: 14, color: this.dark ? '#93969B' : '#8A8D91' })
            Text(this.workspaces.items.find((item: NativeWorkspaceItem) => item.workspaceId === this.workspaceId)?.title || '全部')
              .fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width(88)
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
          }
        }.height(30).padding({ left: 8, right: 8 }).borderRadius(8).backgroundColor(Color.Transparent)
          .onClick(() => { this.workspacePickerOpen = true; })
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'plus-outline', glyphSize: 14, color: this.dark ? '#CFD3D6' : '#61666B' })
        }.width(30).height(30).borderRadius(8).backgroundColor(Color.Transparent)
          .accessibilityText('新建会话或管理工作区')
          .onClick(() => {
            if (this.workspaceId) this.createQuickSession(this.workspaceId);
            else if (this.workspaces.items.length) this.createQuickSession(this.workspaces.items[0].workspaceId);
            else this.openNewSession();
          })
      }.width('100%').padding({ left: 4, top: 4 })
      List({ space: 2 }) {
        LazyForEach(this.sessionSource, (entry: NativeWorkspaceRow) => {
          ListItem() {
            if (entry.group) {
              Row({ space: 6 }) {
                DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 12, color: this.dark ? '#93969B' : '#777A80' })
                  .rotate({ angle: this.collapsedGroups.includes(entry.workspaceId) ? 180 : -90 })
                Text(entry.title).fontSize(12).fontWeight(FontWeight.Medium).layoutWeight(1).fontColor(this.dark ? '#B5B8BD' : '#61666B')
                Text(String(entry.count)).fontSize(11).fontColor(this.dark ? '#93969B' : '#8A8D91')
                if (entry.workspaceId !== 'other') {
                  Button({ type: ButtonType.Normal }) {
                    DSHIcon({ glyph: 'plus-outline', glyphSize: 13, color: this.dark ? '#CFD3D6' : '#61666B' })
                  }.width(30).height(28).borderRadius(8).backgroundColor(Color.Transparent)
                    .accessibilityText('在工作区新建会话')
                    .onClick(() => { this.createQuickSession(entry.workspaceId); })
                }
              }.width('100%').padding({ left: 6, right: 10, top: 9, bottom: 5 })
            } else { this.sessionRow(entry.session) }
          }.onClick(() => {
            if (!entry.group) this.select(entry.session.id);
            else {
              this.collapsedGroups = this.collapsedGroups.includes(entry.workspaceId) ? this.collapsedGroups.filter((id: string) => id !== entry.workspaceId) : this.collapsedGroups.concat([entry.workspaceId]);
              this.sessionsChanged();
            }
          }).accessibilityText(entry.group ? entry.title : entry.session.title + (entry.session.running ? '，运行中' : ''))
        }, (entry: NativeWorkspaceRow) => entry.key)
      }.layoutWeight(1).width('100%').cachedCount(8)
      if (this.workspaceError) {
        Row() {
          Text(this.workspaceError).fontSize(12).layoutWeight(1).fontColor(this.dark ? '#FF9393' : '#C53737')
          Button('重试', { type: ButtonType.Normal }).height(32).fontSize(12).onClick(() => { this.refreshWorkspaces(); })
        }.width('100%')
      }
      if (this.connectionPhase === 'retrying' && !this.selected) {
        Text('连接中断，正在尝试重连').fontSize(11).padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .width('100%').borderRadius(9).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7')
      }
      if (this.loading) { Text('正在连接…').fontSize(13).fontColor(this.dark ? '#CFD3D6' : '#61666B') }
      if (!this.loading && !this.visibleSessionCount) { Text('新建会话，开始你的任务').fontSize(13).fontColor(this.dark ? '#CFD3D6' : '#61666B') }
      Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
      Button({ type: ButtonType.Normal }) {
        Row({ space: 10 }) {
          DSHIcon({ glyph: 'settings-outline', glyphSize: 17, color: this.dark ? '#CFD3D6' : '#61666B' })
          Text('设置').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F1F1F2' : '#25262A')
        }.width('100%').padding({ left: 10, right: 10 })
      }.width('100%').height(44).borderRadius(10).backgroundColor(Color.Transparent)
        .accessibilityText('应用设置').onClick(() => {
          this.closeDrawer();
          this.onSettings();
        })
    }.padding({ left: 12, right: 12, top: this.safeTop + 8, bottom: this.safeBottom + 8 }).height('100%').width('100%')
      .backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.992, y: 0.992 })))
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
            .accessibilityText('打开侧边栏')
            .onClick(() => { this.openDrawer(); })
        }
        Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onClick(() => { this.getUIContext().getPromptAction().showDialog({ title: '会话标题', message: this.title, buttons: [{ text: '关闭', color: this.dark ? '#AFC9FF' : '#315ECA' }] }); })
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'ellipsis-outline', color: this.dark ? '#CFD3D6' : '#61666B' })
        }.width(36).height(36).borderRadius(10)
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .accessibilityText('更多操作').onClick(() => { this.openUtilities(); })
          .bindPopup(this.utilityOpen, { builder: this.utilityMenu, placement: Placement.BottomRight,
            enableArrow: false, targetSpace: 4, radius: 16, mask: true,
            popupColor: this.dark ? '#37383C' : '#F8F9FA', backgroundBlurStyle: BlurStyle.NONE,
            onStateChange: (event): void => { if (!event.isVisible) this.utilityOpen = false; } })
      }.width('100%')
      if (this.connectionPhase === 'retrying') {
        Row({ space: 8 }) {
          Text('•').fontSize(14).fontColor(this.dark ? '#F8C86A' : '#A56A00')
          Text('连接中断，正在尝试重连').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          Blank()
        }.padding({ left: 10, right: 10, top: 6, bottom: 6 }).width('100%').borderRadius(9)
          .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7')
      }
      if ((this.connectionPhase === 'opening' || this.connectionPhase === 'syncing') && !this.model.messages.length) {
        Row({ space: 8 }) { LoadingProgress().width(14).height(14); Text('正在加载会话…').fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91') }
          .width('100%').padding({ left: 4, top: 4, bottom: 4 })
      }
      List({ space: 12, scroller: this.scroller }) {
        if (this.hasMore) {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 4 }) {
                if (this.paging) LoadingProgress().width(12).height(12)
                else DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 12,
                  color: this.dark ? '#93969B' : '#8A8D91' }).rotate({ angle: 90 })
                Text(this.paging ? '读取中' : '更早').fontSize(11)
                  .fontColor(this.dark ? '#93969B' : '#8A8D91')
              }
            }.enabled(!this.paging).height(30).padding({ left: 9, right: 9 }).borderRadius(9)
              .backgroundColor(Color.Transparent).onClick(() => { this.older(); })
          }
        }
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
              Row({ space: 8 }) {
                Text(message.label + (message.text ? ' · ' + message.text : '')).fontSize(11).layoutWeight(1)
                  .fontColor(message.footerOutcome === 'failed' ? '#D55E5E' : this.dark ? '#93969B' : '#8A8D91')
                if (message.footerCopyText) {
                  Button({ type: ButtonType.Normal }) {
                    DSHIcon({ glyph: this.footerCopiedId === message.footerCopyMessageId ?
                      'check-outline' : 'copy-outline', glyphSize: 13,
                      color: this.dark ? '#93969B' : '#8A8D91' })
                  }.width(28).height(28).borderRadius(9).backgroundColor(Color.Transparent)
                    .accessibilityText(this.footerCopiedId === message.footerCopyMessageId ?
                      '答复已复制' : '复制最终答复')
                    .onClick((): void => {
                      this.copyFooter(message.footerCopyText, message.footerCopyMessageId);
                    })
                }
              }.width('100%').constraintSize({ minHeight: 28 })
            } else { Row() {
              if (message.role === 'user') { Blank().layoutWeight(1) }
              NativeMessageView({ client: this.client, sessionId: this.selected, message: message, onCompatibility: this.onCompatibility })
            }.width('100%').alignItems(VerticalAlign.Top) }
          }
        }, (message: NativeMessage) => message.id)
      }.layoutWeight(1).width('100%').cachedCount(6)
        .edgeEffect(NativeExperience.reducedMotion() ? EdgeEffect.None : EdgeEffect.Spring)
        .onReachStart(() => { if (this.userHasScrolled && this.hasMore && this.connectionPhase === 'live') this.older(); })
        .onScrollIndex((first: number) => {
          this.firstVisible = first;
          if (this.userHasScrolled && first <= 20 && this.hasMore && this.connectionPhase === 'live') this.queuePrefetch(1);
        })
        .onScrollFrameBegin((offset: number, state: ScrollState) => { if (state === ScrollState.Scroll) this.userHasScrolled = true; return { offsetRemain: offset }; })
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
          .placeholderColor(this.dark ? '#93969B' : '#8A8D91')
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
            .fontColor(this.dark ? '#CFD3D6' : '#61666B').accessibilityText('模型与推理')
            .onClick(() => { this.utilityOpen = false; this.modelPickerOpen = true; })
            .bindPopup(this.modelPickerOpen, { builder: this.modelPicker, placement: Placement.Top,
              enableArrow: true, targetSpace: 8, radius: 16, mask: false,
              popupColor: this.dark ? '#242527' : '#FFFFFF', backgroundBlurStyle: BlurStyle.NONE,
              onStateChange: (event): void => { if (!event.isVisible) this.modelPickerOpen = false; } })
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
              .enabled(this.connectionPhase === 'live' && !this.sending && !this.uncertain && (this.draft.trim().length > 0 || this.images.length > 0))
              .opacity(this.connectionPhase === 'live' && !this.sending && !this.uncertain && (this.draft.trim().length > 0 || this.images.length > 0) ? 1 : 0.4)
              .accessibilityText(this.sending ? '发送中' : '发送').onClick(() => { this.followTail = true; this.send(); })
          }
        }.width('100%')
      }.padding(8).width('100%').borderRadius(16)
        .border({ width: 0.5, color: this.dark ? '#3B3B3E' : '#DFE1E5' })
        .backgroundColor(this.dark ? '#232324' : '#FFFFFF')
    }.padding({ left: 12, right: 12, top: this.safeTop + 4, bottom: this.safeBottom + 8 })
      .height('100%').layoutWeight(1)
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.992, y: 0.992 })))
  }

  @Builder
  private mainSurface() {
    Column() {
      if (this.selected) {
        this.conversation()
      } else {
        Column({ space: 14 }) {
          Text(this.loading ? '正在恢复会话…' : '开始你的任务').fontSize(22).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          if (!this.loading) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 }) {
                DSHIcon({ glyph: 'new-chat-outline', glyphSize: 17, color: this.dark ? '#151517' : '#FFFFFF' })
                Text('新建会话').fontSize(14)
              }
            }.height(42).padding({ left: 16, right: 16 }).borderRadius(12)
              .backgroundColor(this.dark ? '#F9FAFB' : '#0F1115')
              .fontColor(this.dark ? '#151517' : '#FFFFFF').onClick(() => { this.openNewSession(); })
          } else {
            LoadingProgress().width(22).height(22).color(this.dark ? '#F9FAFB' : '#0F1115')
          }
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
      }
      if (this.archivedUndo) {
        Row() {
          Text('已归档会话').fontSize(12).layoutWeight(1)
          Button('撤销', { type: ButtonType.Normal }).height(36).fontSize(12).backgroundColor(Color.Transparent)
            .onClick(() => {
              const id = this.archivedUndo; this.archivedUndo = '';
              this.client.operation(JSON.stringify({ operation: 'unarchive', sessionId: id }))
                .then(() => { this.refreshSessionList(); }).catch((error: Error) => this.handleError(error));
            })
          Button({ type: ButtonType.Normal }) {
            DSHIcon({ glyph: 'close-outline', glyphSize: 12, color: this.dark ? '#93969B' : '#8A8D91' })
          }.height(36).width(32).backgroundColor(Color.Transparent).onClick(() => { this.archivedUndo = ''; })
        }.padding({ left: 12, right: 8 }).width('100%').backgroundColor(this.dark ? '#232324' : '#F5F6F7')
      }
      if (this.error) {
        Text(this.error).fontSize(12).padding(12).width('100%').fontColor(this.dark ? '#FF9393' : '#C53030')
      }
    }.width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
  }

  @Builder
  private mobileShell() {
    Stack() {
      Column() { this.mainSurface() }.width('100%').height('100%')
      if (this.showSessions) {
        Row() {
          Column() { this.sessionList() }.width(this.mobileDrawerWidth()).height('100%')
            .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
              .onActionEnd((event: GestureEvent): void => {
                if (event.offsetX < -48) this.closeDrawer();
              }))
            .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
              TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -28 })))
          Column().layoutWeight(1).height('100%')
            .backgroundColor(this.dark ? '#66000000' : '#42000000')
            .onClick(() => { this.closeDrawer(); })
            .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY : TransitionEffect.OPACITY)
        }.width('100%').height('100%')
      } else {
        Row().position({ x: 0, y: 0 }).width(18).height('100%').backgroundColor(Color.Transparent)
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
            .onActionEnd((event: GestureEvent): void => {
              if (event.offsetX > 44) this.openDrawer();
            }))
      }
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      if (this.wide) {
        SideBarContainer(SideBarContainerType.Embed) {
          Column() { this.sessionList() }.width('100%').height('100%')
          Column() { this.mainSurface() }.width('100%').height('100%')
        }
        .showSideBar(true)
        .showControlButton(false)
        .autoHide(false)
        .sideBarPosition(SideBarPosition.Start)
        .sideBarWidth(248)
        .minSideBarWidth(248)
        .maxSideBarWidth(248)
        .divider(null)
        .width('100%').height('100%')
        .onAreaChange((_old: Area, area: Area) => {
          this.windowWidth = Number(area.width);
          this.wide = this.windowWidth >= 760;
          this.groupHeight = Math.min(400, Number(area.height) / 2);
          this.navigationChanged();
        })
      } else {
        Column() { this.mobileShell() }.width('100%').height('100%')
          .onAreaChange((_old: Area, area: Area) => {
            this.windowWidth = Number(area.width);
            this.wide = this.windowWidth >= 760;
            this.groupHeight = Math.min(400, Number(area.height) / 2);
            this.navigationChanged();
          })
      }

      if (this.workspacePickerOpen) {
        Column() {
          NativeWorkspacePicker({ client: this.client, snapshot: this.workspaces, sessions: this.sessions,
            selectedId: this.workspaceId,
            onClose: (): void => { this.workspacePickerOpen = false; },
            onSelect: (id: string): void => {
              this.workspaceId = id; this.workspacePickerOpen = false; this.showSessions = true;
            },
            onChanged: (value: NativeWorkspaceSnapshot): void => { this.workspaces = value; } })
        }.width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      }
      if (this.newSessionOpen) {
        Column() { this.newSessionForm() }.width('100%').height('100%')
          .backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      }
      if (this.toolsOpen) {
        NativeSessionTools({ client: this.client, sessionId: this.toolsId,
          sessionTitle: this.sessions.find((item: NativeSession) => item.id === this.toolsId)?.title || this.title,
          onClose: (): void => { this.toolsOpen = false; },
          onRename: (title: string): void => {
            if (this.toolsId === this.selected) this.title = title;
            this.toolsOpen = false; this.refreshSessionList();
          } })
      }
    }.width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
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
