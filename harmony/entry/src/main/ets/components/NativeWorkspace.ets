import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { NativeHarnessClient, NativeHttpError, NativeImageDraft } from '../services/NativeHarnessClient';
import { NativeFrame, NativeMessage, NativeSession, NativeSessionModel, NativePendingQuestion } from '../services/NativeSessionModel';
import { NativeListSource } from '../services/NativeListSource';
import { NativeExperience } from '../services/NativeExperience';
import { NativeTextContent } from './NativeTextContent';
import { NativeInteraction } from './NativeInteraction';
import { NativeSessionTools } from './NativeSessionTools';
import { NativeMessageView } from './NativeMessageView';

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
  onLogin: () => void = (): void => {};
  onSnapshot: (value: string) => Promise<void> = async (): Promise<void> => {};
  onCompatibility: () => void = (): void => {};
  @StorageLink('nativeBackRevision') @Watch('backToSessions') private backRevision: number = 0;
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeRefreshRevision') @Watch('reload') private refreshRevision: number = 0;
  @StorageLink('nativeCompatibilityActive') @Watch('activityChanged') private fallbackActive: boolean = false;
  @StorageLink('nativeAppActive') @Watch('activityChanged') private active: boolean = true;
  @StorageLink('requestedSession') @Watch('openRequested') private requestedSession: string = '';
  @State @Watch('sessionsChanged') private sessions: NativeSession[] = [];
  @State private continued: NativeFrame[] = [];
  @State private interactions: NativeFrame[] = [];
  @State private images: NativeImageDraft[] = [];
  @State private attaching: boolean = false;
  @State private toolsOpen: boolean = false;
  @State private steer: boolean = false;
  @State private newSessionOpen: boolean = false;
  @State private newCwd: string = '';
  @State private newPreset: string = '';
  @State private selected: string = '';
  @State private title: string = '工作空间';
  @State private draft: string = '';
  @State private showSessions: boolean = true;
  @State private wide: boolean = false;
  @State private loading: boolean = true;
  @State private sending: boolean = false;
  @State private connected: boolean = false;
  @State private running: boolean = false;
  @State private waiting: boolean = false;
  @State private uncertain: boolean = false;
  @State private error: string = '';
  @State private paging: boolean = false;
  @State private hasMore: boolean = false;
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

  private sessionsChanged(): void { this.sessionSource.set(this.sessions); }
  aboutToAppear(): void { this.mounted = true; this.reload(); }
  aboutToDisappear(): void {
    this.mounted = false; this.generation++; this.client.pause();
    clearTimeout(this.paintTimer); clearTimeout(this.reconnectTimer); clearTimeout(this.widgetTimer);
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
      this.updateWidget();
      const requested = this.requestedSession || this.client.selectedId;
      if (requested) {
        this.requestedSession = '';
        if (requested === this.selected) {
          const session = this.sessions.find((item: NativeSession) => item.id === requested);
          if (session) this.title = session.title;
          this.follow();
        } else this.select(requested);
      }
    } catch (error) { this.handleError(error as Error); }
    finally { if (this.mounted && generation === this.generation) this.loading = false; }
  }
  private handleError(error: Error): void {
    if (!this.mounted) return;
    if (error instanceof NativeHttpError && error.status === 401) { this.onLogin(); return; }
    this.error = error.message || '连接失败，请刷新或使用兼容模式';
  }
  private activityChanged(): void {
    clearTimeout(this.reconnectTimer); clearTimeout(this.widgetTimer);
    if (!this.active || this.fallbackActive) { this.interactions = []; this.client.pause(); this.connected = false; return; }
    this.updateWidget();
    if (this.selected) this.follow(); else this.reload();
  }
  private animatePane(action: () => void): void {
    if (NativeExperience.reducedMotion()) action();
    else this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, action);
  }
  private backToSessions(): void {
    this.animatePane(() => { this.toolsOpen = false; this.showSessions = true; });
    AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', false);
  }
  private async updateWidget(): Promise<void> {
    clearTimeout(this.widgetTimer);
    if (!this.mounted || !this.active || this.fallbackActive) return;
    try {
      const value = await this.client.request('/pocket/api/overview');
      if (this.mounted && this.active && !this.fallbackActive) await this.onSnapshot(value);
    } catch (_) {}
    finally { if (this.mounted && this.active && !this.fallbackActive) this.widgetTimer = setTimeout(() => { this.updateWidget(); }, 60000); }
  }
  private openRequested(): void {
    if (!this.requestedSession) return;
    const id = this.requestedSession; this.requestedSession = ''; this.select(id);
  }
  private select(id: string): void {
    this.client.drafts.set(this.selected, this.draft);
    this.continued = []; this.interactions = []; this.toolsOpen = false; this.selected = id; this.client.selectedId = id;
    const session = this.sessions.find((item: NativeSession) => item.id === id);
    this.title = session ? session.title : '会话';
    this.draft = this.client.drafts.get(id) || '';
    this.images = this.client.images.get(id) || [];
    this.uncertain = this.client.uncertain.has(id);
    this.animatePane(() => { this.showSessions = false; }); this.followTail = true;
    AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', !this.wide);
    this.model = new NativeSessionModel(); this.source.set([]);
    this.streamText = ''; this.streamReasoning = '';
    this.running = false; this.waiting = false; this.retries = 0;
    this.follow();
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
      this.model.apply(frame);
      if (frame.type === 'snapshot') { this.connected = true; this.error = ''; this.retries = 0; }
      if (this.paintTimer < 0) this.paintTimer = setTimeout(() => { this.paintTimer = -1; this.paint(); }, 40);
    }, (): void => { this.reconnect(id); }).catch((error: Error) => this.handleError(error));
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
    this.interactions = [];
    this.error = '实时连接中断，正在重新同步；不会自动重发消息。';
    if (this.retries >= 5) { this.error = '连接已暂停，请点击刷新，或切换兼容模式。'; return; }
    this.retries++;
    this.reconnectTimer = setTimeout(() => { this.follow(); }, Math.min(15000, 1000 * Math.pow(2, this.retries)));
  }
  private paint(): void {
    if (!this.mounted) return;
    if (this.previousRows !== this.model.messages) { this.previousRows = this.model.messages; this.source.set(this.model.messages); }
    this.running = this.model.running; this.waiting = this.model.waiting; this.hasMore = this.model.hasMore;
    this.streamText = this.model.streamText; this.streamReasoning = this.model.streamReasoning;
    if (this.followTail) setTimeout(() => { if (this.mounted) this.scroller.scrollEdge(Edge.Bottom); }, 0);
  }
  private async create(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    try {
      const id = await this.client.create(this.newCwd, this.newPreset);
      this.newSessionOpen = false;
      if (!this.mounted) return;
      const value = await this.client.sessions();
      this.sessions = value.items; this.select(id);
    } catch (error) { this.handleError(error as Error); }
    finally { this.loading = false; }
  }
  private async send(): Promise<void> {
    if (this.sending || (!this.draft.trim() && !this.images.length) || !this.selected || this.uncertain) return;
    const id = this.selected; const text = this.draft;
    this.sending = true; this.error = '';
    this.client.drafts.set(id, text);
    try {
      await this.client.prompt(id, text, this.steer ? 'steer' : 'queue', this.images);
      this.client.drafts.set(id, ''); this.client.images.delete(id);
      if (this.selected === id) this.images = [];
      if (this.selected === id) this.draft = '';
    } catch (error) { this.uncertain = this.client.uncertain.has(id); this.handleError(error as Error); }
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
    Column({ space: 12 }) {
      Row() {
        Text('会话').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
          .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        Button('新建', { type: ButtonType.Normal }).height(44).borderRadius(12).fontSize(13)
          .backgroundColor(this.dark ? '#353638' : '#EBEEF2').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .enabled(!this.loading).onClick(() => { this.newSessionOpen = true; })
      }.width('100%')
      List({ space: 4 }) {
        LazyForEach(this.sessionSource, (item: NativeSession) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(item.title).fontSize(14).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
              Text(item.running ? '运行中' : '会话').fontSize(11).fontColor(this.dark ? '#CFD3D6' : '#61666B')
            }.padding(12).width('100%').alignItems(HorizontalAlign.Start).borderRadius(12)
              .backgroundColor(this.selected === item.id ? this.dark ? '#353638' : '#EBEEF2' : Color.Transparent)
          }.onClick(() => this.select(item.id)).accessibilityText(item.title + (item.running ? '，运行中' : ''))
        }, (item: NativeSession) => item.id)
      }.layoutWeight(1).width('100%')
      if (this.loading) { Text('正在连接…').fontSize(13).fontColor(this.dark ? '#CFD3D6' : '#61666B') }
      if (!this.loading && !this.sessions.length) { Text('新建会话，开始你的任务').fontSize(13).fontColor(this.dark ? '#CFD3D6' : '#61666B') }
    }.padding(16).height('100%').width(this.wide ? 240 : '100%')
      .backgroundColor(this.dark ? '#232324' : '#F5F6F7').transition(TransitionEffect.OPACITY)
  }

  @Builder
  private conversation() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        if (!this.wide) {
          Button('会话', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
            .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
            .onClick(() => { this.backToSessions(); })
        }
        Text(this.title).fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        Button('工具', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
          .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onClick(() => { this.toolsOpen = true; })
        if (this.running) {
          Button('停止', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
            .backgroundColor(Color.Transparent).fontColor(this.dark ? '#CFD3D6' : '#61666B')
            .onClick(() => { this.client.cancel(this.selected).catch((error: Error) => this.handleError(error)); })
        }
      }.width('100%')
      List({ space: 18, scroller: this.scroller }) {
        if (this.hasMore) { ListItem() { Button(this.paging ? '正在加载…' : '加载更早消息').enabled(!this.paging).height(44).onClick(() => { this.older(); }) } }
        LazyForEach(this.source, (message: NativeMessage) => {
          ListItem() { NativeMessageView({ client: this.client, sessionId: this.selected, message: message, onCompatibility: this.onCompatibility }) }
        }, (message: NativeMessage) => message.id)
        if (this.streamReasoning || this.streamText) {
          ListItem() {
            Column({ space: 8 }) {
              Text('DeepSeek · 正在回复').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
              if (this.streamReasoning) { Text('正在思考…').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B') }
              NativeTextContent({ text: this.streamText })
            }.width('100%').alignItems(HorizontalAlign.Start)
          }
        }
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
        Button('有待处理输入 · 打开完整交互', { type: ButtonType.Normal }).height(44).fontSize(12).borderRadius(12)
          .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onClick(this.onCompatibility)
      }
      if (this.uncertain) {
        Button('发送结果未确认 · 已检查会话，允许再次发送', { type: ButtonType.Normal }).height(44).fontSize(11)
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .onClick(() => { this.client.uncertain.delete(this.selected); this.uncertain = false; })
      }
      if (this.images.length) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.images, (image: NativeImageDraft) => {
              Button(image.name + ' ×').height(44).enabled(!this.sending).onClick(() => {
                this.images = this.images.filter((item: NativeImageDraft) => item.id !== image.id);
                this.client.images.set(this.selected, this.images);
              })
            }, (image: NativeImageDraft) => image.id)
          }
        }.scrollable(ScrollDirection.Horizontal).width('100%')
      }
      Row({ space: 8 }) {
        Button(this.attaching ? '读取中…' : '添加图片').height(44).fontSize(12).enabled(!this.attaching && !this.sending)
          .onClick(() => { this.attach(); })
        Button('更多附件').height(44).fontSize(12).onClick(this.onCompatibility)
        Toggle({ type: ToggleType.Switch, isOn: this.steer }).onChange((value: boolean) => { this.steer = value; })
        Text(this.steer ? '下一步干预' : '下一轮排队').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
      }.width('100%')
      Row({ space: 8 }) {
        TextArea({ text: this.draft, placeholder: '向 Harness 发送消息' }).layoutWeight(1).height(76)
          .fontSize(14).borderRadius(16)
          .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onChange((value: string) => { this.draft = value; this.client.drafts.set(this.selected, value); })
        Button(this.sending ? '发送中' : '发送', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
          .backgroundColor(this.dark ? '#F9FAFB' : '#0F1115').fontColor(this.dark ? '#151517' : '#FFFFFF')
          .enabled(this.connected && !this.sending && !this.uncertain && (this.draft.trim().length > 0 || this.images.length > 0))
          .onClick(() => { this.followTail = true; this.send(); })
      }.width('100%')
    }.padding(16).height('100%').layoutWeight(1).transition(TransitionEffect.OPACITY)
  }

  build() {
    Column() {
      Row() {
        if (this.wide || this.showSessions) { this.sessionList() }
        if (!this.showSessions || this.wide) {
          if (this.selected) {
            if (this.toolsOpen) {
              NativeSessionTools({ client: this.client, sessionId: this.selected, sessionTitle: this.title,
                onClose: (): void => { this.toolsOpen = false; },
                onSelect: (id: string): void => { this.select(id); this.reload(); },
                onRename: (title: string): void => { this.title = title; this.reload(); },
                onCompatibility: this.onCompatibility }).layoutWeight(1)
            } else { this.conversation() }
          }
          else {
            Column({ space: 16 }) {
              Text('开始你的任务').fontSize(24).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
              Text('选择一个会话，或新建会话连接 Harness。').fontSize(14).fontColor(this.dark ? '#CFD3D6' : '#61666B')
              Button('新建会话', { type: ButtonType.Normal }).height(44).borderRadius(12).fontSize(14)
                .backgroundColor(this.dark ? '#F9FAFB' : '#0F1115').fontColor(this.dark ? '#151517' : '#FFFFFF')
                .enabled(!this.loading).onClick(() => { this.newSessionOpen = true; })
            }.layoutWeight(1).height('100%').justifyContent(FlexAlign.Center).padding(24)
          }
        }
      }.width('100%').layoutWeight(1)
      if (this.newSessionOpen) {
        Column({ space: 8 }) {
          Text('新建会话').fontSize(16).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          TextInput({ text: this.newCwd, placeholder: '工作目录（留空使用默认目录）' }).onChange((value: string) => { this.newCwd = value; })
          TextInput({ text: this.newPreset, placeholder: 'Agent Preset（留空使用默认配置）' }).onChange((value: string) => { this.newPreset = value; })
          Row({ space: 8 }) {
            Button('取消').height(44).onClick(() => { this.newSessionOpen = false; })
            Button('创建').height(44).enabled(!this.loading).onClick(() => { this.create(); })
          }
        }.padding(16).width('100%')
      }
      if (this.error) {
        Text(this.error).fontSize(12).padding(12).fontColor(this.dark ? '#FF9393' : '#C53030')
      }
    }.width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      .onAreaChange((_old: Area, area: Area) => { this.wide = Number(area.width) >= 760;
        AppStorage.setOrCreate<boolean>('nativeWorkspaceCanGoBack', !this.wide && !this.showSessions); })
  }
}
