import { NativeHarnessClient } from '../services/NativeHarnessClient';
import {
  NativeCatalogModel,
  NativeModelDirectoryState,
  NativeModelEffort,
  NativeModelProvider,
  NativeModelSelection
} from '../services/NativeModelDirectory';
import { DSHIcon } from './DSHIcon';

/** Compact composer popover. It paints the per-session cache before refreshing. */
@Component
export struct NativeModelPicker {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop currentCaption: string = '模型';
  onClose: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeModelRevision') @Watch('modelChanged') private modelRevision: number = 0;
  @State private directory: NativeModelDirectoryState = new NativeModelDirectoryState();
  @State private query: string = '';
  @State private loading: boolean = false;
  @State private busy: boolean = false;
  @State private error: string = '';
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.directory = this.client.modelDirectory.state(this.sessionId);
    this.refresh();
  }
  aboutToDisappear(): void {
    this.mounted = false;
  }
  private modelChanged(): void {
    if (this.mounted) this.directory = this.client.modelDirectory.state(this.sessionId);
  }
  private currentModel(): NativeCatalogModel | undefined {
    return this.directory.catalog.groups.find((row: NativeModelProvider) => row.id === this.directory.selected.provider)?.models
      .find((row: NativeCatalogModel) => row.id === this.directory.selected.model);
  }
  private modelCount(): number {
    return this.directory.catalog.groups.reduce((sum: number, provider: NativeModelProvider) => sum + provider.models.length, 0);
  }
  private async refresh(): Promise<void> {
    this.loading = this.modelCount() === 0;
    this.error = '';
    try {
      const value = await this.client.modelDirectory.load(this.sessionId);
      if (this.mounted) this.directory = value;
    } catch (_) {
      if (this.mounted) this.error = this.modelCount() ? '刷新失败，显示缓存' : '模型目录加载失败';
    } finally {
      if (this.mounted) this.loading = false;
    }
  }
  private async choose(provider: string, model: NativeCatalogModel, effort: string, closeAfter: boolean): Promise<void> {
    if (this.busy) return;
    const selectedEffort = this.directory.selected.reasoningEffort || this.currentModel()?.reasoning?.defaultEffort || '';
    if (provider === this.directory.selected.provider && model.id === this.directory.selected.model &&
      (effort || model.reasoning?.defaultEffort || '') === selectedEffort) {
      if (closeAfter) this.onClose();
      return;
    }
    this.busy = true;
    this.error = '';
    const route = new NativeModelSelection();
    route.provider = provider;
    route.model = model.id;
    route.reasoningEffort = effort;
    try {
      await this.client.modelDirectory.select(this.sessionId, route);
      if (this.mounted) {
        this.directory = this.client.modelDirectory.state(this.sessionId);
        if (closeAfter) this.onClose();
      }
    } catch (_) {
      if (this.mounted) this.error = '切换失败';
    } finally {
      if (this.mounted) this.busy = false;
    }
  }
  @Builder
  private choice(title: string, detail: string, selected: boolean, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(title).fontSize(13).fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#F9FAFB' : '#17181B')
          if (detail) {
            Text(detail).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (selected) { DSHIcon({ glyph: 'check-outline', glyphSize: 14, color: this.dark ? '#F9FAFB' : '#17181B' }) }
      }.width('100%')
    }.width('100%').height(detail ? 46 : 38).padding({ left: 9, right: 9 }).borderRadius(10)
      .backgroundColor(selected ? this.dark ? '#353638' : '#F1F3F5' : Color.Transparent)
      .enabled(enabled && !this.busy).onClick(action)
  }
  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('模型与推理').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#F9FAFB' : '#17181B')
          Text(this.currentCaption).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.dark ? '#93969B' : '#8A8D91')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.busy || this.loading) { LoadingProgress().width(16).height(16) }
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'close-outline', glyphSize: 13, color: this.dark ? '#93969B' : '#8A8D91' })
        }.width(30).height(30).backgroundColor(Color.Transparent).onClick(this.onClose).accessibilityText('关闭模型选择')
      }.width('100%').padding({ left: 2, right: 2 })
      if (this.modelCount() > 4) {
        TextInput({ text: this.query, placeholder: '搜索模型' }).height(34).fontSize(12).borderRadius(9)
          .backgroundColor(this.dark ? '#232324' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#17181B')
          .placeholderColor(this.dark ? '#93969B' : '#8A8D91').onChange((value: string) => { this.query = value; })
      }
      Scroll() {
        Column({ space: 3 }) {
          ForEach(this.directory.catalog.groups, (provider: NativeModelProvider) => {
            if (provider.models.some((model: NativeCatalogModel) => !this.query ||
              (model.name + ' ' + model.id).toLowerCase().includes(this.query.toLowerCase()))) {
              Text(provider.name).fontSize(10).fontWeight(FontWeight.Medium).padding({ left: 9, top: 5, bottom: 2 })
                .fontColor(this.dark ? '#93969B' : '#8A8D91')
            }
            ForEach(provider.models.filter((model: NativeCatalogModel) => !this.query ||
              (model.name + ' ' + model.id).toLowerCase().includes(this.query.toLowerCase())), (model: NativeCatalogModel) => {
              this.choice(model.name, model.id === model.name ? '' : model.id,
                this.directory.selected.provider === provider.id && this.directory.selected.model === model.id, true,
                () => { this.choose(provider.id, model, model.reasoning?.defaultEffort || '', !model.reasoning); })
            }, (model: NativeCatalogModel) => provider.id + ':' + model.id)
          }, (provider: NativeModelProvider) => provider.id)
          if (this.currentModel()?.reasoning) {
            Text('推理').fontSize(10).fontWeight(FontWeight.Medium).padding({ left: 9, top: 8, bottom: 2 })
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
            this.choice('默认', '', !this.directory.selected.reasoningEffort, true, () => {
              const model = this.currentModel();
              if (model) this.choose(this.directory.selected.provider, model, '', true);
            })
            ForEach(this.currentModel()?.reasoning?.efforts || [], (effort: NativeModelEffort) => {
              this.choice(effort.name, effort.description,
                (this.directory.selected.reasoningEffort || this.currentModel()?.reasoning?.defaultEffort) === effort.id,
                true, () => {
                  const model = this.currentModel();
                  if (model) this.choose(this.directory.selected.provider, model, effort.id, true);
                })
            }, (effort: NativeModelEffort) => effort.id)
          }
          if (this.loading && !this.modelCount()) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16)
              Text(this.currentCaption).fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
            }.height(44).padding({ left: 9 })
          }
          if (!this.loading && !this.modelCount()) {
            Text('此服务未提供模型目录').fontSize(12).padding({ left: 9, top: 10, bottom: 10 })
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ maxHeight: 340 }).align(Alignment.Top)
      if (this.error) {
        Row() {
          Text(this.error).fontSize(11).layoutWeight(1).fontColor(this.dark ? '#FF9393' : '#C53737')
          Button('重试', { type: ButtonType.Normal }).height(30).fontSize(11).enabled(!this.busy).onClick(() => { this.refresh(); })
        }.width('100%')
      }
    }.width(320).padding(10).borderRadius(16).backgroundColor(this.dark ? '#242527' : '#FFFFFF')
  }
}
