import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NativeHarnessClient, NativeHttpError, NativeImageDraft } from '../services/NativeHarnessClient';
import { NativeFrame, NativeMessage, NativeSession, NativeSessionModel, NativePendingQuestion,
  NativeWorkspaceItem, NativeWorkspaceSnapshot, NativeWorkspaceRow, NativeImagePreviewRequest,
  NativeFileViewRequest, nativeWorkspaceRows, nativeToolsParent, nativeWorkspaceDragOrder,
  nativeBackToBottomAvailable, nativeBackToBottomHasNewContent } from '../services/NativeSessionModel';
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
import { NativeNavigationState, nativeSessionMenu, nativeCanGoBack, nativeForkTitle,
  nativeUtilityMenu } from '../services/NativeNavigation';
import { NativeMenuItem } from '../services/NativeNavigation';
import { NativeMetadataCache } from '../services/NativeMetadataCache';
import { NativeTranscriptCache } from '../services/NativeTranscriptCache';
import { NativeMotion } from '../services/NativeMotion';
import { NativeImageLightbox } from './NativeImageLightbox';
import { NativeFilePreview } from './NativeFilePreview';
import { NativeFileBrowser } from './NativeFileBrowser';

class NativeExportCapabilities { copyMarkdown: boolean = false; downloadLog: boolean = false; }
class NativeWorkspaceOrderRequest {
  operation: string = 'workspaceOrder';
  workspaceId: string;
  beforeWorkspaceId?: string;
  constructor(workspaceId: string) {
    this.workspaceId = workspaceId;
  }
}
function cloneWorkspaceSnapshot(value: NativeWorkspaceSnapshot): NativeWorkspaceSnapshot {
  const clone = new NativeWorkspaceSnapshot();
  clone.available = value.available;
  clone.archivedSessionIds = value.archivedSessionIds.slice();
  clone.pinnedSessionIds = value.pinnedSessionIds.slice();
  clone.items = value.items.map((item: NativeWorkspaceItem): NativeWorkspaceItem => {
    const row = new NativeWorkspaceItem();
    row.workspaceId = item.workspaceId;
    row.path = item.path;
    row.title = item.title;
    row.sessionIds = item.sessionIds.slice();
    return row;
  });
  return clone;
}
class NativeWorkspaceOrderOperation {
  request: NativeWorkspaceOrderRequest;
  next: NativeWorkspaceSnapshot;
  generation: number;
  constructor(request: NativeWorkspaceOrderRequest, next: NativeWorkspaceSnapshot, generation: number) {
    this.request = request;
    this.next = next;
    this.generation = generation;
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
  @StorageLink('nativeImagePreviewRevision') @Watch('imagePreviewChanged') private imagePreviewRevision: number = 0;
  @StorageLink('nativeFileViewRevision') @Watch('fileViewChanged') private fileViewRevision: number = 0;
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
  @State private imagePreviewOpen: boolean = false;
  @State private imagePreview: NativeImagePreviewRequest = new NativeImagePreviewRequest();
  @State private fileViewOpen: boolean = false;
  @State private fileView: NativeFileViewRequest = new NativeFileViewRequest();
  @State private attaching: boolean = false;
  @State @Watch('navigationChanged') private toolsOpen: boolean = false;
  @State private toolsId: string = '';
  @State @Watch('navigationChanged') private modelPickerOpen: boolean = false;
  @State @Watch('navigationChanged') private menuId: string = '';
  @State private menuTarget: string = '';
  @State @Watch('navigationChanged') private utilityOpen: boolean = false;
  @State private copying: boolean = false;
  @State private modelCaption: string = '模型';
  @State private downloading: boolean = false;
  @State private utilityKnown: boolean = false;
  @State private exportCapabilities: NativeExportCapabilities = new NativeExportCapabilities();
  private utilityCapabilities: Map<string, NativeExportCapabilities> = new Map<string, NativeExportCapabilities>();
  private utilityRequests: Set<string> = new Set<string>();
  @State private menuBusy: boolean = false;
  @State private archivedUndo: string = '';
  @State private steer: boolean = false;
  @State @Watch('navigationChanged') private newSessionOpen: boolean = false;
  @State @Watch('navigationChanged') private workspacePickerOpen: boolean = false;
  @State private workspacePickerPage: string = 'root';
  @State private workspacePickerDirection: number = 1;
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
  @State private dragWorkspaceId: string = '';
  @State private dropWorkspaceId: string = '';
  @State private dropWorkspaceAfter: boolean = false;
  @State private backToBottomVisible: boolean = false;
  @State private backToBottomNew: boolean = false;
  @State private drawerFollowing: boolean = false;
  @State private drawerTranslation: number = 0;
  @State private transcriptViewportHeight: number = 0;
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
  private visibleRows: NativeMessage[] = [];
  private firstVisible: number = 0;
  private userHasScrolled: boolean = false;
  private prefetchQueue: number = 0;
  private prefetching: boolean = false;
  private selectionGeneration: number = 0;
  private cacheTimer: number = -1;
  private backToBottomTimer: number = -1;
  private returnToBottomTimer: number = -1;
  private returningToBottom: boolean = false;
  private workspaceOrderGeneration: number = 0;
  private workspaceOrderBusy: boolean = false;
  private workspaceOrderQueue: NativeWorkspaceOrderOperation[] = [];
  private workspaceOrderConfirmed: NativeWorkspaceSnapshot | null = null;
  private drawerSettleTimer: number = -1;
  private destinationTimer: number = -1;
  private utilityOpenedAt: number = 0;
  private interactionTimes: Map<string, number> = new Map<string, number>();
  private workspaceRowRects: Map<string, number[]> = new Map<string, number[]>();

  private preferencesChanged(): void { this.steer = this.client.hostSettings.chat().busyEnter === 'steer'; this.renderTranscript(); }
  private modelCaptionChanged(): void { this.modelCaption = this.client.modelDirectory.caption(this.selected); }

  private navigationChanged(): void {
    const state = new NativeNavigationState();
    state.wide = this.wide; state.drawerOpen = this.showSessions;
    state.drawerPage = this.searchOpen ? 'search' : 'primary';
    state.picker = this.workspacePickerOpen;
    state.create = this.newSessionOpen; state.tools = this.toolsOpen;
    state.menu = !!this.menuId || this.utilityOpen || this.modelPickerOpen;
    state.imagePreview = this.imagePreviewOpen;
    state.filePreview = this.fileViewOpen;
    AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', nativeCanGoBack(state));
    AppStorage.setOrCreate<boolean>('nativeWorkspaceHasSelection', this.selected.length > 0);
  }
  private imagePreviewChanged(): void {
    const raw = AppStorage.get<string>('nativeImagePreviewPayload') || '';
    if (!raw) return;
    try {
      const parsed = JSON.parse(raw) as NativeImagePreviewRequest;
      if (!parsed.sessionId || !parsed.attachment?.attachmentId) return;
      const request = new NativeImagePreviewRequest();
      request.sessionId = parsed.sessionId;
      request.attachment = parsed.attachment;
      this.imagePreview = request;
      this.imagePreviewOpen = true;
      this.navigationChanged();
    } catch (_) {}
  }
  private closeImagePreview(): void {
    this.imagePreviewOpen = false;
    AppStorage.setOrCreate<string>('nativeImagePreviewPayload', '');
    this.navigationChanged();
  }
  private fileViewChanged(): void {
    const raw = AppStorage.get<string>('nativeFileViewPayload') || '';
    if (!raw) return;
    try {
      const parsed = JSON.parse(raw) as NativeFileViewRequest;
      if (!parsed.sessionId || typeof parsed.path !== 'string' ||
        (parsed.kind !== 'file' && parsed.kind !== 'browser') ||
        (parsed.kind === 'file' && !parsed.path)) return;
      const request = new NativeFileViewRequest();
      request.kind = parsed.kind;
      request.sessionId = parsed.sessionId;
      request.path = parsed.path;
      if (parsed.kind === 'browser') {
        this.client.rememberBrowsePath(parsed.sessionId, parsed.path);
      } else {
        const clean = parsed.path.replace(/\\/g, '/');
        const slash = clean.lastIndexOf('/');
        this.client.rememberBrowsePath(parsed.sessionId, slash >= 0 ? clean.slice(0, slash) : '');
      }
      this.fileView = request;
      this.fileViewOpen = true;
      this.navigationChanged();
    } catch (_) {}
  }
  private closeFileView(): void {
    this.fileViewOpen = false;
    AppStorage.setOrCreate<string>('nativeFileViewPayload', '');
    this.navigationChanged();
  }
  private workspaceRootFor(sessionId: string): string {
    const session = this.sessions.find((item: NativeSession): boolean => item.id === sessionId);
    if (session?.cwd) return session.cwd;
    const workspace = this.workspaces.items.find((item: NativeWorkspaceItem): boolean =>
      item.sessionIds.includes(sessionId));
    return workspace?.path || '';
  }

  private sessionsChanged(): void {
    const visible = nativeWorkspaceRows(this.sessions, this.workspaces, this.workspaceId, this.query, this.client.models,
      this.selected, this.collapsedGroups, this.interactionTimes);
    this.visibleSessionCount = visible.filter((row: NativeWorkspaceRow) => !row.group).length;
    this.sessionSource.set(visible, (row: NativeWorkspaceRow): string => row.key);
  }
  aboutToAppear(): void { this.mounted = true; this.reload(); }
  aboutToDisappear(): void {
    this.mounted = false; this.generation++; this.client.pause();
    clearTimeout(this.paintTimer); clearTimeout(this.reconnectTimer); clearTimeout(this.widgetTimer);
    clearTimeout(this.widgetEventTimer);
    clearTimeout(this.backgroundTimer); clearTimeout(this.preloadTimer);
    clearTimeout(this.cacheTimer); clearTimeout(this.backToBottomTimer);
    clearTimeout(this.returnToBottomTimer);
    clearTimeout(this.drawerSettleTimer);
    clearTimeout(this.destinationTimer);
    this.persistCache();
    this.stopBackground();
    AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', false);
    AppStorage.setOrCreate<boolean>('nativeWorkspaceHasSelection', false);
  }
  private async reload(): Promise<void> {
    const generation = ++this.generation;
    await this.client.prepareCacheKey();
    this.interactionTimes = NativeMetadataCache.interactions(
      this.context, this.client.cacheKey());
    const cached = NativeMetadataCache.read(this.context, this.client.cacheKey());
    if (cached.sessions.length) {
      this.sessions = cached.sessions;
      if (cached.workspaces) this.workspaces = cached.workspaces;
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
      if (!this.selected) this.openDrawer(false);
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
        if (!this.workspaceOrderBusy) this.workspaceOrderConfirmed = cloneWorkspaceSnapshot(nextWorkspaces);
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
        else this.openDrawer(false);
      } else this.openDrawer(false);
    } catch (error) {
      if (!this.sessions.length) this.handleError(error as Error);
      if (!(error instanceof NativeHttpError && error.status === 401)) {
        if (!this.sessions.length) {
          this.connectionPhase = 'retrying';
          this.scheduleReconnect('');
        } else {
          this.connectionPhase = this.selected ? 'syncing' : 'idle';
          if (!this.selected) this.openDrawer(false);
          if (!this.selected) {
            clearTimeout(this.reconnectTimer);
            this.reconnectTimer = setTimeout((): void => {
              if (this.mounted && this.active) this.reload();
            }, 5000);
          }
        }
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
    NativeMotion.animate(this.getUIContext(), 'surface', action);
  }
  private mobileDrawerWidth(): number {
    return Math.max(240, Math.min(380, this.windowWidth * 0.86, this.windowWidth - 48));
  }
  private setDrawerState(open: boolean): void {
    this.drawerFollowing = false;
    this.drawerTranslation = open ? 0 : -this.mobileDrawerWidth();
    this.showSessions = open;
  }
  private openDrawer(refresh: boolean = true): void {
    if (this.showSessions || this.drawerFollowing) {
      if (refresh) this.refreshSessionList().catch((): void => {});
      return;
    }
    clearTimeout(this.backToBottomTimer);
    clearTimeout(this.returnToBottomTimer);
    clearTimeout(this.drawerSettleTimer);
    const width = this.mobileDrawerWidth();
    this.drawerFollowing = true;
    this.showSessions = false;
    this.drawerTranslation = -width;
    this.backToBottomVisible = false;
    this.returningToBottom = false;
    NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
      this.drawerTranslation = 0;
    });
    this.drawerSettleTimer = setTimeout((): void => {
      if (!this.mounted) return;
      this.showSessions = true;
      this.drawerFollowing = false;
      this.navigationChanged();
    }, NativeMotion.enabled() ? NativeMotion.duration('surface') : 0);
    if (refresh) this.refreshSessionList().catch((): void => {});
  }
  private closeDrawer(): void {
    clearTimeout(this.drawerSettleTimer);
    this.drawerFollowing = true;
    const width = this.mobileDrawerWidth();
    NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
      this.drawerTranslation = -width;
    });
    this.drawerSettleTimer = setTimeout((): void => {
      if (!this.mounted) return;
      this.showSessions = false;
      this.drawerFollowing = false;
      this.drawerTranslation = -width;
      this.navigationChanged();
    }, NativeMotion.enabled() ? NativeMotion.duration('surface') : 0);
    this.restoreScrollTailAfterDrawer();
  }
  private openDrawerDestination(destination: string): void {
    clearTimeout(this.destinationTimer);
    this.closeDrawer();
    // Temporary product gate: keep the original compatibility routing here for
    // restoration after these entries have a native implementation.
    // Mounting the web surface from the drawer row's press handler can race
    // the native drawer teardown on some devices. Commit it on the next task.
    // this.destinationTimer = setTimeout((): void => {
    //   if (this.mounted) this.onDestination(destination);
    // }, 0);
    this.getUIContext().getPromptAction().showToast({
      message: '功能未开放',
      duration: 1600
    });
  }
  private toggleWorkspaceGroup(id: string): void {
    NativeMotion.animate(this.getUIContext(), 'micro', (): void => {
      this.collapsedGroups = this.collapsedGroups.includes(id) ?
        this.collapsedGroups.filter((value: string): boolean => value !== id) :
        this.collapsedGroups.concat([id]);
      this.sessionsChanged();
    });
  }
  private restoreScrollTailAfterDrawer(): void {
    setTimeout((): void => {
      if (this.mounted && !this.showSessions) this.updateScrollTail();
    }, NativeMotion.enabled() ? NativeMotion.duration('surface') + 10 : 0);
  }
  private drawerProgress(width: number): number {
    return Math.max(0, Math.min(1, (this.drawerTranslation + width) / Math.max(1, width)));
  }
  private beginDrawerPan(): void {
    clearTimeout(this.drawerSettleTimer);
    clearTimeout(this.backToBottomTimer);
    this.backToBottomVisible = false;
    this.drawerFollowing = true;
    this.drawerTranslation = this.showSessions ? 0 : -this.mobileDrawerWidth();
  }
  private updateDrawerPan(event: GestureEvent): void {
    const width = this.mobileDrawerWidth();
    const start = this.showSessions ? 0 : -width;
    this.drawerFollowing = true;
    this.drawerTranslation = Math.max(-width, Math.min(0, start + event.offsetX));
  }
  private settleDrawerPan(event: GestureEvent): void {
    const width = this.mobileDrawerWidth();
    const progress = this.drawerProgress(width);
    clearTimeout(this.drawerSettleTimer);
    if (this.showSessions) {
      const dismiss = progress < 0.62 || event.offsetX < -48;
      NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
        this.drawerTranslation = dismiss ? -width : 0;
      });
      this.drawerSettleTimer = setTimeout((): void => {
        if (!this.mounted) return;
        if (dismiss) {
          this.showSessions = false;
          this.drawerTranslation = -width;
        }
        this.drawerFollowing = false;
        this.navigationChanged();
        if (dismiss) this.restoreScrollTailAfterDrawer();
      }, NativeMotion.enabled() ? NativeMotion.duration('surface') : 0);
      return;
    }
    const open = progress > 0.38 || event.offsetX > 44;
    NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
      this.drawerTranslation = open ? 0 : -width;
    });
    this.drawerSettleTimer = setTimeout((): void => {
      if (!this.mounted) return;
      if (open) this.showSessions = true;
      else this.drawerTranslation = -width;
      this.drawerFollowing = false;
      this.navigationChanged();
      if (!open) this.restoreScrollTailAfterDrawer();
    }, NativeMotion.enabled() ? NativeMotion.duration('surface') : 0);
  }
  private cancelDrawerPan(): void {
    const width = this.mobileDrawerWidth();
    clearTimeout(this.drawerSettleTimer);
    NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
      this.drawerTranslation = this.showSessions ? 0 : -width;
    });
    this.drawerSettleTimer = setTimeout((): void => {
      if (!this.mounted) return;
      this.drawerFollowing = false;
      if (!this.showSessions) this.drawerTranslation = -width;
      if (!this.showSessions) this.restoreScrollTailAfterDrawer();
    }, NativeMotion.enabled() ? NativeMotion.duration('surface') : 0);
  }
  private backToSessions(): void {
    if (this.imagePreviewOpen) { this.closeImagePreview(); return; }
    if (this.fileViewOpen) {
      if (this.fileView.kind === 'browser') return;
      this.closeFileView();
      return;
    }
    if (this.menuId || this.utilityOpen) { this.menuId = ''; this.utilityOpen = false; return; }
    if (this.modelPickerOpen) { this.modelPickerOpen = false; return; }
    if (this.workspacePickerOpen) {
      if (this.workspacePickerPage !== 'root') this.setWorkspacePickerPage('root');
      else this.closeWorkspacePicker();
      return;
    }
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
  private openWorkspacePicker(): void {
    this.workspacePickerPage = 'root';
    this.workspacePickerDirection = 1;
    NativeMotion.animate(this.getUIContext(), 'navigation', (): void => { this.workspacePickerOpen = true; });
  }
  private setWorkspacePickerPage(page: string): void {
    this.workspacePickerDirection = page === 'root' ? -1 : 1;
    NativeMotion.animate(this.getUIContext(), 'navigation', (): void => { this.workspacePickerPage = page; });
  }
  private closeWorkspacePicker(): void {
    NativeMotion.animate(this.getUIContext(), 'navigation', (): void => { this.workspacePickerOpen = false; });
  }
  private openTools(page: string, id: string = this.selected): void {
    this.toolsId = id; AppStorage.setOrCreate<string>('nativeSessionToolsPage', page); this.toolsOpen = true;
  }
  private async refreshSessionList(workspaceOrderGeneration: number = -1): Promise<void> {
    const expectedGeneration = workspaceOrderGeneration >= 0 ?
      workspaceOrderGeneration : this.workspaceOrderGeneration;
    const rows = await this.client.sessions();
    if (!this.mounted || expectedGeneration !== this.workspaceOrderGeneration) return;
    this.sessions = rows.items;
    const nextWorkspaces = await this.client.workspaces();
    if (!this.mounted || expectedGeneration !== this.workspaceOrderGeneration) return;
    if (nextWorkspaces.available) {
      this.workspaces = nextWorkspaces;
      if (!this.workspaceOrderBusy) this.workspaceOrderConfirmed = cloneWorkspaceSnapshot(nextWorkspaces);
      this.workspaceError = '';
    } else {
      this.workspaceError = '工作区加载失败';
    }
    NativeMetadataCache.save(this.context, this.client.cacheKey(), this.sessions,
      this.workspaces.available ? this.workspaces : null);
  }
  private async sessionAction(action: string): Promise<void> {
    const id = this.menuTarget; this.menuId = '';
    if (!id || this.menuBusy || this.workspaceOrderBusy) return;
    if (action === 'rename') { this.openTools('rename', id); return; }
    if (action === 'copyId') {
      pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, id))
        .then(() => { this.getUIContext().getPromptAction().showToast({ message: '已复制' }); }).catch(() => { this.error = '复制失败'; });
      return;
    }
    this.menuBusy = true;
    let pinRollback: NativeWorkspaceSnapshot | null = null;
    try {
      if (action === 'fork') {
        const reply = JSON.parse(await this.client.operation(JSON.stringify({ operation: 'fork', sessionId: id }))) as Record<string, Object>;
        const source = this.sessions.find((item: NativeSession) => item.id === id);
        try {
          if (source?.titleKnown && typeof reply.sessionId === 'string') await this.client.operation(JSON.stringify({ operation: 'rename', sessionId: reply.sessionId, title: nativeForkTitle(source.title) }));
        } catch (_) { this.error = '分支已创建，标题更新失败'; }
        await this.refreshSessionList(); return;
      }
      if (action === 'pin' || action === 'unpin') {
        const previous = cloneWorkspaceSnapshot(this.workspaces);
        pinRollback = previous;
        const next = cloneWorkspaceSnapshot(previous);
        const ids = new Set<string>(previous.pinnedSessionIds);
        if (action === 'pin') ids.add(id); else ids.delete(id);
        next.pinnedSessionIds = Array.from(ids);
        NativeMotion.animate(this.getUIContext(), 'micro', (): void => {
          this.workspaces = next; this.sessionsChanged();
        });
      }
      try { await this.client.operation(JSON.stringify({ operation: action, sessionId: id })); }
      catch (error) {
        if (action !== 'archive' || !(error instanceof NativeHttpError) || error.code !== 'workspace/session-active') throw error as Error;
        const choice = await this.getUIContext().getPromptAction().showDialog({ title: '停止活动并归档？',
          buttons: [{ text: '取消', color: '#777A80' }, { text: '停止并归档', color: '#C53737' }] });
        if (choice.index !== 1) return;
        await this.client.operation(JSON.stringify({ operation: 'archive', sessionId: id, stopActivity: true }));
      }
      if (action === 'pin' || action === 'unpin') {
        pinRollback = null;
        this.workspaceOrderConfirmed = null;
      }
      if (!this.mounted) return;
      if (action === 'archive') {
        this.archivedUndo = id;
        if (this.selected === id) {
          this.client.pause(); this.selected = ''; this.client.selectedId = ''; this.setDrawerState(true);
          NativeMetadataCache.forgetSession(this.context, this.client.cacheKey());
          NativeTranscriptCache.forgetSession(this.context, this.client.cacheKey(), id).catch(() => {});
        }
      }
      await this.refreshSessionList();
    } catch (error) {
      if (pinRollback && this.mounted) {
        this.workspaces = pinRollback;
        this.sessionsChanged();
        this.getUIContext().getPromptAction().showToast({
          message: action === 'pin' ? '置顶未保存' : '取消置顶未保存', duration: 1500
        });
      }
      this.handleError(error as Error);
    }
    finally { this.menuBusy = false; }
  }
  private beginWorkspaceDrag(id: string): CustomBuilder | DragItemInfo {
    if (id && id !== 'other' && id !== 'pinned') this.dragWorkspaceId = id;
    return this.workspaceDragBuilder;
  }
  private cancelWorkspaceDrag(): void {
    this.dragWorkspaceId = '';
    this.dropWorkspaceId = '';
    this.dropWorkspaceAfter = false;
  }
  private async drainWorkspaceOrders(first: NativeWorkspaceOrderOperation): Promise<void> {
    if (this.workspaceOrderBusy) return;
    this.workspaceOrderBusy = true;
    let operation: NativeWorkspaceOrderOperation | null = first;
    let lastSuccessfulGeneration = -1;
    try {
      while (operation && this.mounted) {
        try {
          await this.client.operation(JSON.stringify(operation.request));
          this.workspaceOrderConfirmed = cloneWorkspaceSnapshot(operation.next);
          lastSuccessfulGeneration = operation.generation;
        } catch (error) {
          this.workspaceOrderQueue = [];
          if (this.mounted) {
            if (this.workspaceOrderConfirmed) {
              this.workspaces = cloneWorkspaceSnapshot(this.workspaceOrderConfirmed);
              this.sessionsChanged();
            }
            this.getUIContext().getPromptAction().showToast({
              message: '工作区顺序未保存', duration: 1500
            });
            this.handleError(error as Error);
          }
          break;
        }
        const nextOperation = this.workspaceOrderQueue.shift();
        operation = nextOperation || null;
      }
    } finally {
      if (!this.mounted) this.workspaceOrderQueue = [];
      this.workspaceOrderBusy = false;
    }
    if (this.mounted && lastSuccessfulGeneration >= 0) {
      try {
        await this.refreshSessionList(lastSuccessfulGeneration);
      } catch (_) {
        if (this.mounted) this.workspaceError = '工作区顺序已保存，刷新失败';
      }
    }
  }
  private dropWorkspace(target: string, event: DragEvent): void {
    const sourceId = this.dragWorkspaceId;
    this.cancelWorkspaceDrag();
    if (!sourceId || !target || sourceId === target || target === 'other' || target === 'pinned' ||
      this.menuBusy || this.query.trim()) {
      event.setResult(DragResult.DROP_DISABLED);
      return;
    }
    event.setResult(DragResult.DROP_ENABLED);
    const rect = this.workspaceRowRects.get(target) || [];
    const after = rect.length >= 2 && event.getWindowY() > rect[0] + rect[1] / 2;
    const order = this.workspaces.items.map((item: NativeWorkspaceItem): string => item.workspaceId);
    const nextOrder = nativeWorkspaceDragOrder(order, sourceId, target, after);
    if (!nextOrder) return;
    const byId: Map<string, NativeWorkspaceItem> = new Map<string, NativeWorkspaceItem>();
    this.workspaces.items.forEach((item: NativeWorkspaceItem): void => { byId.set(item.workspaceId, item); });
    const previous = this.workspaces;
    const next = cloneWorkspaceSnapshot(previous);
    next.items = nextOrder.map((id: string): NativeWorkspaceItem => {
      const source = byId.get(id) as NativeWorkspaceItem;
      const row = new NativeWorkspaceItem();
      row.workspaceId = source.workspaceId; row.path = source.path; row.title = source.title;
      row.sessionIds = source.sessionIds.slice();
      return row;
    });
    const generation = ++this.workspaceOrderGeneration;
    NativeMotion.spring(this.getUIContext(), (): void => {
      this.workspaces = next; this.sessionsChanged();
    });
    const sourceIndex = nextOrder.indexOf(sourceId);
    const beforeWorkspaceId = sourceIndex >= 0 ? nextOrder[sourceIndex + 1] || '' : '';
    const request = new NativeWorkspaceOrderRequest(sourceId);
    if (beforeWorkspaceId) request.beforeWorkspaceId = beforeWorkspaceId;
    const operation = new NativeWorkspaceOrderOperation(request, next, generation);
    if (this.workspaceOrderBusy) {
      this.workspaceOrderQueue.push(operation);
      return;
    }
    this.workspaceOrderConfirmed = cloneWorkspaceSnapshot(previous);
    this.drainWorkspaceOrders(operation);
  }
  @Builder
  private workspaceDragBuilder() {
    Row({ space: 7 }) {
      DSHIcon({ glyph: 'drag-handle-outline', glyphSize: 14,
        color: this.dark ? '#F9FAFB' : '#17181B' })
      Text(this.workspaces.items.find((item: NativeWorkspaceItem): boolean =>
        item.workspaceId === this.dragWorkspaceId)?.title || '工作区')
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
    NativeActionMenu({ items: this.utilityItems(),
      onSelect: (id: string): void => { this.utilityAction(id); } })
  }
  @Builder
  private utilityOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          if (Date.now() - this.utilityOpenedAt > 250) this.utilityOpen = false;
        })
      Column() { this.utilityMenu() }
        .width(208).margin({ top: this.safeTop + 40, right: 12 })
        .borderRadius(16)
        .backgroundColor(this.dark ? '#232324' : '#FFFFFF')
        .clip(true)
        .shadow({ radius: 16, color: this.dark ? '#99000000' : '#2E000000', offsetY: 5 })
        .transition(NativeMotion.rowTransition())
    }.width('100%').height('100%')
  }
  @Builder
  private modelPicker() {
    NativeModelPicker({ client: this.client, sessionId: this.selected, currentCaption: this.modelCaption,
      onClose: (): void => { this.modelPickerOpen = false; } })
  }
  private utilityItems(): NativeMenuItem[] {
    return nativeUtilityMenu(this.utilityKnown, this.exportCapabilities.copyMarkdown,
      this.exportCapabilities.downloadLog, this.copying, this.downloading);
  }
  private utilityAction(id: string): void {
    if (id === 'files') {
      if (!this.selected) return;
      this.utilityOpen = false;
      const request = new NativeFileViewRequest();
      request.kind = 'browser';
      request.sessionId = this.selected;
      request.path = this.client.lastBrowsePath(this.selected);
      this.fileView = request;
      this.fileViewOpen = true;
      this.navigationChanged();
      return;
    }
    if (id === 'copy') this.copyMarkdown();
    else if (id === 'download') this.downloadLog();
  }
  private openUtilities(): void {
    this.modelPickerOpen = false;
    const next = !this.utilityOpen;
    if (next) this.utilityOpenedAt = Date.now();
    // Conditional presentation layers must commit on the first frame. Their
    // NativeMotion transitions animate the inserted menu without delaying state.
    this.utilityOpen = next;
    if (!next) return;
    // The action list is complete on the first frame. Capabilities only refine
    // availability and never gate whether the menu can appear immediately.
    this.prefetchUtilities(this.selected);
  }
  private async prefetchUtilities(id: string): Promise<void> {
    if (!id || this.utilityCapabilities.has(id) || this.utilityRequests.has(id)) return;
    this.utilityRequests.add(id);
    try {
      const value = JSON.parse(await this.client.operation(JSON.stringify({ operation: 'capabilities', sessionId: id }))) as NativeExportCapabilities;
      this.utilityCapabilities.set(id, value);
      if (this.mounted && this.selected === id) {
        this.exportCapabilities = value;
        this.utilityKnown = true;
      }
    } catch (_) {
      const unsupported = new NativeExportCapabilities();
      this.utilityCapabilities.set(id, unsupported);
      if (this.mounted && this.selected === id) {
        this.exportCapabilities = unsupported;
        this.utilityKnown = true;
      }
    } finally {
      this.utilityRequests.delete(id);
    }
  }
  private async refreshWorkspaces(): Promise<void> {
    if (this.workspaceLoading) return;
    this.workspaceLoading = true; this.workspaceError = '';
    try {
      const value = await this.client.workspaces();
      if (!value.available) throw new Error('Workspace unavailable');
      if (this.mounted) {
        this.workspaces = value;
        if (!this.workspaceOrderBusy) this.workspaceOrderConfirmed = cloneWorkspaceSnapshot(value);
      }
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
    this.openWorkspacePicker();
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
        this.openDrawer(false);
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
    this.animatePane(() => { this.selected = id; this.setDrawerState(false); }); this.followTail = true;
    this.interactionTimes = NativeMetadataCache.rememberInteraction(
      this.context, this.client.cacheKey(), id);
    this.sessionsChanged();
    NativeMetadataCache.rememberSession(this.context, this.client.cacheKey(), id);
    NativeTranscriptCache.saveRoute(this.context, this.client.cacheKey(), id).catch(() => {});
    this.navigationChanged();
    this.model = this.client.models.get(id) || new NativeSessionModel();
    this.client.models.set(id, this.model);
    const capabilities = this.utilityCapabilities.get(id);
    this.utilityKnown = capabilities !== undefined;
    this.exportCapabilities = capabilities || new NativeExportCapabilities();
    this.prefetchUtilities(id);
    this.previousRows = this.model.messages;
    this.renderTranscript();
    this.streamText = ''; this.streamReasoning = '';
    this.running = false; this.waiting = false; this.retries = 0;
    this.connectionPhase = 'syncing'; this.userHasScrolled = false;
    clearTimeout(this.backToBottomTimer);
    clearTimeout(this.returnToBottomTimer);
    this.backToBottomVisible = false; this.backToBottomNew = false;
    this.returningToBottom = false;
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
      if (nativeBackToBottomHasNewContent(this.followTail, frame.type)) {
        this.backToBottomNew = true;
      }
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
    if (this.followTail && !this.returningToBottom) {
      setTimeout(() => {
        if (this.mounted && this.followTail && !this.returningToBottom) this.scroller.scrollEdge(Edge.Bottom);
      }, 0);
    }
  }
  private renderTranscript(): void {
    const rows = nativeTranscript(this.model.messages, this.model.running, this.model.streamTools, this.model.streamReasoning, this.model.streamText);
    const visible = nativePresentTranscript(rows, this.client.hostSettings.chat(), this.model.turnDisclosure, this.model.collapseThrough);
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
      this.interactionTimes = NativeMetadataCache.rememberInteraction(
        this.context, this.client.cacheKey(), id);
      this.sessionsChanged();
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
  private isScrollAtEnd(): boolean {
    let atEnd = false;
    try { atEnd = this.scroller.isAtEnd(); } catch (_) {}
    return atEnd;
  }
  private settleScrollTail(): void {
    clearTimeout(this.returnToBottomTimer);
    const atEnd = this.isScrollAtEnd();
    this.returningToBottom = false;
    if (atEnd) {
      clearTimeout(this.backToBottomTimer);
      this.backToBottomVisible = false;
      this.backToBottomNew = false;
      this.followTail = true;
      return;
    }
    this.userHasScrolled = true;
    this.followTail = false;
    this.backToBottomVisible = true;
  }
  private updateScrollTail(): void {
    const atEnd = this.isScrollAtEnd();
    if (atEnd) {
      clearTimeout(this.backToBottomTimer);
      this.backToBottomVisible = false;
      this.backToBottomNew = false;
      this.followTail = true;
      this.returningToBottom = false;
      return;
    }
    if (!nativeBackToBottomAvailable(atEnd, this.userHasScrolled, this.returningToBottom)) return;
    this.followTail = false;
    clearTimeout(this.backToBottomTimer);
    this.backToBottomTimer = setTimeout((): void => {
      if (this.mounted && !this.followTail) this.backToBottomVisible = true;
    }, 100);
  }
  private returnToBottom(): void {
    if (!this.selected || !this.visibleRows.length) return;
    clearTimeout(this.backToBottomTimer);
    this.backToBottomVisible = false;
    this.backToBottomNew = false;
    this.followTail = true;
    this.returningToBottom = true;
    const lastIndex = this.visibleRows.length - 1 + (this.hasMore ? 1 : 0);
    if (!NativeMotion.enabled()) {
      try { this.scroller.scrollToIndex(lastIndex, false, ScrollAlign.END); } catch (_) {}
      try { this.scroller.scrollEdge(Edge.Bottom); } catch (_) {}
      this.returnToBottomTimer = setTimeout((): void => {
        if (this.mounted && this.returningToBottom) this.settleScrollTail();
      }, 0);
      return;
    }
    try { this.scroller.scrollToIndex(lastIndex, true, ScrollAlign.END); } catch (_) {}
    this.returnToBottomTimer = setTimeout((): void => {
      if (!this.mounted || !this.returningToBottom) return;
      try { this.scroller.scrollEdge(Edge.Bottom); } catch (_) {}
      this.settleScrollTail();
    }, 320);
  }

  @Builder
  private sessionRow(row: NativeWorkspaceRow) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(row.session.title.trim() || '未命名会话').fontSize(14).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        if (row.section === 'pinnedSession' && row.workspaceTitle) {
          Text(row.workspaceTitle).fontSize(10).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            .fontColor(this.dark ? '#93969B' : '#8A8D91')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (row.session.running) {
        Text('运行中').fontSize(10).fontColor(this.dark ? '#C7D8FF' : '#3B5B9A')
      }
      if (row.pinned) {
        DSHIcon({ glyph: 'pin-fill', glyphSize: 12, color: this.dark ? '#93969B' : '#8A8D91' })
      }
      if (row.session.blank !== true) {
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'ellipsis-outline',
            color: this.menuId === row.session.id ?
              this.dark ? '#F9FAFB' : '#17181B' : this.dark ? '#93969B' : '#8A8D91' })
        }
          .width(34).height(34).padding(6).borderRadius(8)
          .backgroundColor(this.menuId === row.session.id ?
            this.dark ? '#45464B' : '#DBDEE4' : Color.Transparent).enabled(!this.menuBusy)
          .accessibilityText(row.session.title + '，会话操作')
          .onClick(() => { this.menuTarget = row.session.id; this.menuId = row.session.id; })
          .bindPopup(this.menuId === row.session.id, { builder: this.sessionMenu, placement: Placement.BottomRight,
            enableArrow: false, targetSpace: 4, radius: 16, mask: true,
            popupColor: this.dark ? '#37383C' : '#F8F9FA', backgroundBlurStyle: BlurStyle.NONE,
            onStateChange: (event): void => {
              if (!event.isVisible && this.menuId === row.session.id) this.menuId = '';
            } })
      }
    }.padding({ left: 10, right: 4, top: 5, bottom: 5 }).width('100%').constraintSize({ minHeight: 44 }).borderRadius(10)
      .backgroundColor(this.wide && this.selected === row.session.id ?
        this.dark ? '#2C2C2E' : '#EBEEF2' : Color.Transparent)
      .animation(NativeMotion.implicit('micro'))
      .transition(NativeMotion.workspaceChildrenTransition())
  }

  @Builder
  private workspaceHeader(entry: NativeWorkspaceRow) {
    Row({ space: 6 }) {
      DSHIcon({ glyph: entry.section === 'pinnedHeader' ? 'pin-fill' : 'chevron-left-outline',
        glyphSize: 12, color: this.dark ? '#93969B' : '#777A80' })
        .rotate({ angle: entry.section === 'pinnedHeader' ? 0 :
          this.collapsedGroups.includes(entry.workspaceId) ? 180 : -90 })
      Text(entry.title).fontSize(12).fontWeight(FontWeight.Medium).layoutWeight(1)
        .fontColor(this.dark ? '#B5B8BD' : '#61666B')
      Text(String(entry.count)).fontSize(11).fontColor(this.dark ? '#93969B' : '#8A8D91')
      if (entry.section === 'pinnedHeader') {
        DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 12,
          color: this.dark ? '#93969B' : '#777A80' })
          .rotate({ angle: this.collapsedGroups.includes(entry.workspaceId) ? 180 : -90 })
          .animation(NativeMotion.implicit('micro'))
      }
      if (entry.section === 'workspaceHeader') {
        DSHIcon({ glyph: 'drag-handle-outline', glyphSize: 13,
          color: this.dragWorkspaceId === entry.workspaceId ?
            this.dark ? '#8AB4FF' : '#3964FE' : this.dark ? '#777A80' : '#A2A5AA' })
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'plus-outline', glyphSize: 13,
            color: this.dark ? '#CFD3D6' : '#61666B' })
        }.width(34).height(34).borderRadius(8).backgroundColor(Color.Transparent)
          .accessibilityText('在工作区新建会话')
          .onClick(() => { this.createQuickSession(entry.workspaceId); })
      }
    }.width('100%').constraintSize({ minHeight: 44 }).padding({ left: 6, right: 6 })
      .border({
        width: {
          top: this.dropWorkspaceId === entry.workspaceId && !this.dropWorkspaceAfter ? 2 : 0,
          bottom: this.dropWorkspaceId === entry.workspaceId && this.dropWorkspaceAfter ? 2 : 0
        },
        color: this.dark ? '#8AB4FF' : '#3964FE'
      })
      .opacity(this.dragWorkspaceId === entry.workspaceId ? 0.72 : 1)
      .scale({ x: this.dragWorkspaceId === entry.workspaceId ? 1.01 : 1,
        y: this.dragWorkspaceId === entry.workspaceId ? 1.01 : 1 })
      .animation(NativeMotion.implicit('micro'))
      .draggable(entry.section === 'workspaceHeader' && !this.menuBusy && !this.query.trim())
      .onDragStart((): CustomBuilder | DragItemInfo => this.beginWorkspaceDrag(entry.workspaceId))
      .onDragEnter((): void => {
        if (entry.section !== 'workspaceHeader' || entry.workspaceId === this.dragWorkspaceId) return;
        this.dropWorkspaceId = entry.workspaceId;
        this.dropWorkspaceAfter = false;
      })
      .onDragMove((event: DragEvent): void => {
        if (entry.section !== 'workspaceHeader' || entry.workspaceId === this.dragWorkspaceId) return;
        const rect = this.workspaceRowRects.get(entry.workspaceId) || [];
        this.dropWorkspaceId = entry.workspaceId;
        this.dropWorkspaceAfter = rect.length >= 2 &&
          event.getWindowY() > rect[0] + rect[1] / 2;
      })
      .onDragLeave((): void => {
        if (this.dropWorkspaceId === entry.workspaceId) this.dropWorkspaceId = '';
      })
      .onDrop((event: DragEvent): void => { this.dropWorkspace(entry.workspaceId, event); })
      .onDragEnd((): void => { this.cancelWorkspaceDrag(); })
      .onAreaChange((_old: Area, area: Area): void => {
        this.workspaceRowRects.set(entry.workspaceId,
          [Number(area.globalPosition.y), Number(area.height)]);
      })
      .transition(NativeMotion.rowTransition())
  }

  @Builder
  private sessionList(inMobileDrawer: boolean = false) {
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
            NativeMotion.animate(this.getUIContext(), 'micro', (): void => {
              this.searchOpen = !this.searchOpen;
            });
          })
        if (!this.wide) {
          Button({ type: ButtonType.Circle }) {
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
          .onClick(() => { this.openDrawerDestination('plugins'); })
        Row({ space: 10 }) {
          DSHIcon({ glyph: 'plan-outline', glyphSize: 17, color: this.dark ? '#CFD3D6' : '#61666B' })
          Text('自动化任务').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F1F1F2' : '#25262A')
        }.width('100%').height(40).padding({ left: 10, right: 10 })
          .onClick(() => { this.openDrawerDestination('automation'); })
        Row({ space: 10 }) {
          DSHIcon({ glyph: 'ellipsis-outline', glyphSize: 17, color: this.dark ? '#CFD3D6' : '#61666B' })
          Text('更多').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F1F1F2' : '#25262A')
        }.width('100%').height(40).padding({ left: 10, right: 10 })
          .onClick(() => { this.openDrawerDestination('more'); })
      }.width('100%')
      if (this.searchOpen) {
        TextInput({ text: this.query, placeholder: '搜索工作区和会话' }).height(36).fontSize(13).borderRadius(10)
          .placeholderColor(this.dark ? '#93969B' : '#8A8D91')
          .backgroundColor(this.dark ? '#232324' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onChange((value: string) => { this.query = value; })
          .transition(NativeMotion.rowTransition())
      }
      Row() {
        Text('工作区').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#B5B8BD' : '#61666B')
        Blank()
        Button({ type: ButtonType.Normal }) {
          Row({ space: 5 }) {
            DSHIcon({ glyph: 'browse-outline', glyphSize: 14, color: this.dark ? '#93969B' : '#8A8D91' })
            Text(this.workspaces.items.find((item: NativeWorkspaceItem) => item.workspaceId === this.workspaceId)?.title || '全部')
              .fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 110 })
              .textAlign(TextAlign.End)
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
          }
        }.height(30).padding({ left: 8, right: 0 }).borderRadius(8).backgroundColor(Color.Transparent)
          .onClick(() => { this.openWorkspacePicker(); })
      }.width('100%').padding({ left: 4, right: 0, top: 4 })
      List({ space: 2 }) {
        LazyForEach(this.sessionSource, (entry: NativeWorkspaceRow) => {
          ListItem() {
            Column() {
              if (entry.group) this.workspaceHeader(entry)
              else this.sessionRow(entry)
            }.width('100%').padding({ right: 8 })
          }.onClick(() => {
            if (!entry.group) this.select(entry.session.id);
            else this.toggleWorkspaceGroup(entry.workspaceId);
          }).accessibilityText(entry.group ? entry.title :
            entry.session.title + (entry.pinned ? '，已置顶' : '') +
            (entry.section === 'pinnedSession' && entry.workspaceTitle ?
              '，工作区 ' + entry.workspaceTitle : '') +
            (entry.session.running ? '，运行中' : ''))
        }, (entry: NativeWorkspaceRow) => entry.key)
      }.layoutWeight(1).width('100%').margin({ right: -8 }).cachedCount(8).scrollBar(BarState.Auto)
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
    }.padding({ left: 12, right: 12, top: this.safeTop + (inMobileDrawer ? 6 : 8),
      bottom: this.safeBottom + 8 }).height('100%').width('100%')
      .backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      .transition(NativeMotion.navigationTransition())
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
          .backgroundColor(this.utilityOpen ? this.dark ? '#353638' : '#EBEEF2' : Color.Transparent)
          .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .animation(NativeMotion.implicit('press'))
          .accessibilityText('更多操作').onClick(() => { this.openUtilities(); })
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
      Stack({ alignContent: Alignment.BottomEnd }) {
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
                NativeProcessView({ client: this.client, sessionId: this.selected, message,
                  disclosures: this.model.disclosures,
                  maxExpandedHeight: Math.max(180, this.transcriptViewportHeight * 0.6),
                  maxChildExpandedHeight: Math.max(120, this.transcriptViewportHeight * 0.36) })
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
        }.width('100%').height('100%').cachedCount(6)
          .edgeEffect(NativeExperience.reducedMotion() ? EdgeEffect.None : EdgeEffect.Spring)
          .onReachStart(() => { if (this.userHasScrolled && this.hasMore && this.connectionPhase === 'live') this.older(); })
          .onScrollIndex((first: number) => {
            this.firstVisible = first;
            if (this.userHasScrolled && first <= 20 && this.hasMore && this.connectionPhase === 'live') this.queuePrefetch(1);
          })
          .onScrollFrameBegin((offset: number, state: ScrollState) => {
            if (state === ScrollState.Scroll && !this.returningToBottom) {
              this.userHasScrolled = true;
            }
            return { offsetRemain: offset };
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down && this.returningToBottom) {
              clearTimeout(this.returnToBottomTimer);
              this.returningToBottom = false;
              this.userHasScrolled = true;
              this.updateScrollTail();
            }
          })
          .onScroll(() => { this.updateScrollTail(); })
        if (this.backToBottomVisible && !this.menuId && !this.utilityOpen &&
          !this.modelPickerOpen && !this.toolsOpen && !this.workspacePickerOpen &&
          !this.showSessions) {
          Button({ type: ButtonType.Normal }) {
            Stack({ alignContent: Alignment.Center }) {
              DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 16,
                color: this.dark ? '#F9FAFB' : '#17181B' }).rotate({ angle: -90 })
              if (this.backToBottomNew) {
                Text('').position({ x: 15, y: -15 }).width(6).height(6).borderRadius(6)
                  .backgroundColor(this.dark ? '#8AB4FF' : '#3964FE')
                }
            }.width('100%').height('100%')
          }.width(44).height(44).padding(0).borderRadius(22).clip(true)
            .backgroundColor(this.dark ? '#2C2C2E' : '#FFFFFF')
            .border({ width: 0.5, color: this.dark ? '#4A4B4F' : '#D8DADF' })
            .shadow({ radius: 10, color: this.dark ? '#66000000' : '#22000000', offsetY: 3 })
            .margin({ right: 4, bottom: 8 })
            .accessibilityText(this.backToBottomNew ? '回到底部，有新内容' : '回到底部')
            .onClick((): void => { this.returnToBottom(); })
            .transition(NativeMotion.rowTransition())
        }
      }.layoutWeight(1).width('100%')
        .onAreaChange((_old: Area, area: Area): void => {
          const height = Number(area.height);
          if (height > 0 && height !== this.transcriptViewportHeight) this.transcriptViewportHeight = height;
        })
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
    }.padding({ left: 12, right: 12, top: this.safeTop + 4,
      bottom: Math.ceil(this.safeBottom * 1.2) + 8 })
      .height('100%').layoutWeight(1)
      .transition(NativeMotion.navigationTransition())
  }

  @Builder
  private mainSurface() {
    Column() {
      if (this.selected) {
        this.conversation()
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
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
          if (!this.wide) {
            Button({ type: ButtonType.Normal }) {
              DSHIcon({ glyph: 'panel-left-outline', color: this.dark ? '#F9FAFB' : '#0F1115' })
            }.width(36).height(36).borderRadius(10).padding(0)
              .backgroundColor(this.dark ? '#2C2C2E' : '#FFFFFF')
              .border({ width: 0.5, color: this.dark ? '#45464A' : '#DDE0E5' })
              .margin({ left: 12, top: this.safeTop + 8 })
              .accessibilityText('打开侧边栏')
              .onClick((): void => { this.openDrawer(); })
          }
        }.width('100%').height('100%')
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
    Stack({ alignContent: Alignment.TopStart }) {
      Column() { this.mainSurface() }.width('100%').height('100%')
      Column()
        .width('100%').height('100%')
        .backgroundColor(this.dark ? '#66000000' : '#3D000000')
        .opacity(this.drawerProgress(this.mobileDrawerWidth()))
        .hitTestBehavior(this.showSessions || this.drawerFollowing ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => { this.closeDrawer(); })
      Column() { this.sessionList(true) }.width(this.mobileDrawerWidth()).height('100%')
        .translate({ x: this.showSessions || this.drawerFollowing ? this.drawerTranslation : -this.mobileDrawerWidth() })
        .visibility(this.showSessions || this.drawerFollowing ? Visibility.Visible : Visibility.Hidden)
        .hitTestBehavior(this.showSessions || this.drawerFollowing ? HitTestMode.Default : HitTestMode.None)
        .shadow({
          radius: 20,
          color: this.dark ? '#99000000' : '#33000000',
          offsetX: 5,
          offsetY: 0
        })
        .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
          .onActionStart((): void => { this.beginDrawerPan(); })
          .onActionUpdate((event: GestureEvent): void => { this.updateDrawerPan(event); })
          .onActionEnd((event: GestureEvent): void => { this.settleDrawerPan(event); })
          .onActionCancel((): void => { this.cancelDrawerPan(); }))
      if (!this.showSessions) {
        Row().position({ x: 0, y: 0 }).width(18).height('100%').backgroundColor(Color.Transparent)
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
            .onActionStart((): void => { this.beginDrawerPan(); })
            .onActionUpdate((event: GestureEvent): void => { this.updateDrawerPan(event); })
            .onActionEnd((event: GestureEvent): void => { this.settleDrawerPan(event); })
            .onActionCancel((): void => { this.cancelDrawerPan(); }))
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
          this.navigationChanged();
        })
      } else {
        Column() { this.mobileShell() }.width('100%').height('100%')
          .onAreaChange((_old: Area, area: Area) => {
            this.windowWidth = Number(area.width);
            this.wide = this.windowWidth >= 760;
            this.navigationChanged();
          })
      }

      if (this.utilityOpen) { this.utilityOverlay() }
      if (this.workspacePickerOpen) {
        Column() {
          NativeWorkspacePicker({ client: this.client, snapshot: this.workspaces, sessions: this.sessions,
            selectedId: this.workspaceId, page: this.workspacePickerPage,
            navigationDirection: this.workspacePickerDirection,
            onClose: (): void => { this.closeWorkspacePicker(); },
            onPageChange: (page: string): void => { this.setWorkspacePickerPage(page); },
            onSelect: (id: string): void => {
              this.workspaceId = id; this.closeWorkspacePicker(); this.setDrawerState(true);
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
      if (this.fileViewOpen) {
        if (this.fileView.kind === 'browser') {
          NativeFileBrowser({ client: this.client, sessionId: this.fileView.sessionId,
            workspaceRoot: this.workspaceRootFor(this.fileView.sessionId),
            path: this.fileView.path, onClose: (): void => { this.closeFileView(); } })
        } else {
          NativeFilePreview({ client: this.client, sessionId: this.fileView.sessionId,
            path: this.fileView.path, onClose: (): void => { this.closeFileView(); } })
        }
      }
      if (this.imagePreviewOpen) {
        NativeImageLightbox({ client: this.client, sessionId: this.imagePreview.sessionId,
          attachment: this.imagePreview.attachment,
          onClose: (): void => { this.closeImagePreview(); } })
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
