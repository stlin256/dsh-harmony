import { NativeHarnessClient } from '../services/NativeHarnessClient';

class Effort { id: string = ''; name: string = ''; description: string = ''; }
class Reasoning { efforts: Effort[] = []; defaultEffort: string = ''; }
class Model { id: string = ''; name: string = ''; description: string = ''; reasoning: Reasoning | null = null; }
class Provider { id: string = ''; name: string = ''; models: Model[] = []; }
class CatalogFailure { id: string = ''; name: string = ''; message: string = ''; }
class Catalog { groups: Provider[] = []; failures: CatalogFailure[] = []; }
class QueuedPart { type: string = ''; text: string = ''; }
class QueuedItem { id: string = ''; placement: string = ''; content: QueuedPart[] = []; }
class SessionState { queue: QueuedItem[] | null = null; }
class ForkResult { sessionId: string = ''; }

/** Native controls backed by the same public Session commands as the Harness UI. */
@Component
export struct NativeSessionTools {
  client: NativeHarnessClient = new NativeHarnessClient('');
  @Prop sessionId: string = '';
  @Prop sessionTitle: string = '';
  onClose: () => void = (): void => {};
  onSelect: (id: string) => void = (_id: string): void => {};
  onRename: (title: string) => void = (_title: string): void => {};
  onCompatibility: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private title: string = '';
  @State private catalog: Catalog = new Catalog();
  @State private queue: QueuedItem[] = [];
  @State private projection: string = '';
  @State private editingId: string = '';
  @State private editingText: string = '';
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private status: string = '';
  private mounted: boolean = false;

  aboutToAppear(): void { this.mounted = true; this.title = this.sessionTitle; this.refresh(); }
  aboutToDisappear(): void { this.mounted = false; }
  private async refresh(): Promise<void> {
    this.busy = true; this.error = '';
    const catalog = this.client.operation(JSON.stringify({ operation: 'modelCatalog' }));
    const state = this.client.operation(JSON.stringify({ operation: 'state', sessionId: this.sessionId }));
    const projection = this.client.operation(JSON.stringify({ operation: 'projections', sessionId: this.sessionId }));
    // Each catalog can fail independently; still expose queue and context.
    await Promise.all([
      catalog.then((value: string) => { if (this.mounted) this.catalog = JSON.parse(value) as Catalog; }).catch(() => { if (this.mounted) this.error = '模型目录暂不可用'; }),
      state.then((value: string) => { if (this.mounted) this.queue = (JSON.parse(value) as SessionState).queue || []; }).catch(() => { if (this.mounted) this.error = '队列暂不可用'; }),
      projection.then((value: string) => { if (this.mounted) this.projection = JSON.stringify(JSON.parse(value), null, 2); }).catch(() => {})
    ]);
    if (this.mounted) this.busy = false;
  }
  private async command(body: string): Promise<string> {
    if (this.busy) throw new Error('请等待当前操作完成');
    this.busy = true; this.error = ''; this.status = '';
    try {
      const value = await this.client.operation(body);
      if (this.mounted) this.status = '操作已完成';
      return value;
    } catch (_) {
      if (this.mounted) this.error = '操作未确认，请刷新核对；不会自动重试。';
      throw new Error('Operation unconfirmed');
    } finally { if (this.mounted) this.busy = false; }
  }
  private choose(provider: string, model: string, effort: string = ''): void {
    this.command(JSON.stringify({ operation: 'selectModel', sessionId: this.sessionId, provider, model,
      reasoningEffort: effort || undefined })).catch(() => {});
  }
  private mutateQueue(item: QueuedItem, kind: string): void {
    this.command(JSON.stringify({ operation: 'updateQueue', sessionId: this.sessionId, itemId: item.id,
      kind, text: this.editingText })).then(() => { this.editingId = ''; this.refresh(); }).catch(() => {});
  }
  @Builder
  private action(label: string, run: () => void) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
      .backgroundColor(this.dark ? '#353638' : '#EBEEF2').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
      .enabled(!this.busy).onClick(run)
  }
  build() {
    Column({ space: 12 }) {
      Row() {
        Text('会话工具').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('返回对话').height(44).onClick(this.onClose)
      }.width('100%')
      Scroll() {
        Column({ space: 18 }) {
          Text('会话').fontSize(16).fontWeight(FontWeight.Medium)
          TextInput({ text: this.title, placeholder: '会话名称' }).onChange((value: string) => { this.title = value; })
          Row({ space: 8 }) {
            this.action('重命名', () => {
              if (!this.title.trim()) return;
              this.command(JSON.stringify({ operation: 'rename', sessionId: this.sessionId, title: this.title }))
                .then(() => { if (this.mounted) this.onRename(this.title); }).catch(() => {});
            })
            this.action('创建分支', () => {
              this.command(JSON.stringify({ operation: 'fork', sessionId: this.sessionId }))
                .then((value: string) => { if (this.mounted) this.onSelect((JSON.parse(value) as ForkResult).sessionId); }).catch(() => {});
            })
          }
          Text('模型与推理强度').fontSize(16).fontWeight(FontWeight.Medium)
          ForEach(this.catalog.groups, (provider: Provider) => {
            Text(provider.name).fontSize(14).fontWeight(FontWeight.Medium)
            ForEach(provider.models, (model: Model) => {
              Column({ space: 8 }) {
                this.action(model.name, () => { this.choose(provider.id, model.id); })
                if (model.description) { Text(model.description).fontSize(12) }
                if (model.reasoning) {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(model.reasoning.efforts, (effort: Effort) => {
                      this.action(effort.name, () => { this.choose(provider.id, model.id, effort.id); })
                    }, (effort: Effort) => effort.id)
                  }
                }
              }.padding(12).width('100%').alignItems(HorizontalAlign.Start)
                .borderRadius(12).backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7')
            }, (model: Model) => model.id)
          }, (provider: Provider) => provider.id)
          ForEach(this.catalog.failures, (failure: CatalogFailure) => { Text(failure.name + '：' + failure.message).fontSize(12) })
          Text('排队消息').fontSize(16).fontWeight(FontWeight.Medium)
          if (!this.queue.length) { Text('当前没有待发送的排队消息').fontSize(13) }
          ForEach(this.queue, (item: QueuedItem) => {
            Column({ space: 8 }) {
              Text(item.placement === 'steering' ? '下一步干预' : item.placement === 'context' ? '上下文' : '下一轮').fontSize(12)
              ForEach(item.content, (part: QueuedPart) => { Text(part.text || JSON.stringify(part)).fontSize(14).copyOption(CopyOptions.InApp) })
              if (this.editingId === item.id) {
                TextArea({ text: this.editingText }).height(120).onChange((value: string) => { this.editingText = value; })
                this.action('保存修改', () => { this.mutateQueue(item, 'edit'); })
              }
              Flex({ wrap: FlexWrap.Wrap }) {
                this.action('编辑', () => { this.editingId = item.id; this.editingText = item.content.filter((part: QueuedPart) => part.type === 'text').map((part: QueuedPart) => part.text).join('\n'); })
                this.action('立即干预', () => { this.mutateQueue(item, 'steer'); })
                this.action('移除', () => { this.mutateQueue(item, 'remove'); })
              }
            }.padding(12).width('100%').alignItems(HorizontalAlign.Start).borderRadius(12)
              .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7')
          }, (item: QueuedItem) => item.id)
          Text('会话上下文与投影').fontSize(16).fontWeight(FontWeight.Medium)
          Text(this.projection).fontSize(12).fontFamily('monospace').copyOption(CopyOptions.InApp)
          this.action('刷新状态', () => { this.refresh(); })
          this.action('打开完整工作空间', this.onCompatibility)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%')
      if (this.busy) { Text('正在处理…').fontSize(12) }
      if (this.error) { Text(this.error).fontSize(12).fontColor(this.dark ? '#FF9393' : '#C53030') }
      if (this.status) { Text(this.status).fontSize(12) }
    }.padding(16).width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      .foregroundColor(this.dark ? '#F9FAFB' : '#0F1115')
  }
}
