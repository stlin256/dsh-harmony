import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeMessage } from '../services/NativeSessionModel';
import { NativeMessageView } from './NativeMessageView';
import { NativeToolCallView } from './NativeToolCallView';
import { DSHIcon } from './DSHIcon';
import { nativeProcessIcon } from '../services/NativeTranscript';
import { NativeMotion } from '../services/NativeMotion';

@Component
export struct NativeProcessView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  disclosures: Map<string, boolean> = new Map<string, boolean>();
  @Prop @Watch('changed') message: NativeMessage = new NativeMessage();
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private expanded: boolean = false;
  @State private headline: string = '';
  private titleTimer: number = -1;
  private shownAt: number = 0;
  private disclosureId: string = '';
  private syncDisclosure(): void {
    const key = this.message.turnKey + '|' + this.message.id;
    if (key === this.disclosureId) return;
    this.disclosureId = key;
    this.expanded = this.disclosures.get(key) === true;
  }
  aboutToAppear(): void { this.expanded = this.disclosures.get(this.message.turnKey + '|' + this.message.id) === true; this.changed(); }
  aboutToDisappear(): void { clearTimeout(this.titleTimer); }
  private changed(): void {
    clearTimeout(this.titleTimer);
    const remaining = 150 - (Date.now() - this.shownAt);
    const update = (): void => { this.headline = this.message.label; this.shownAt = Date.now(); };
    if (this.message.closed || remaining <= 0 || !this.headline) update();
    else this.titleTimer = setTimeout(update, remaining);
    this.syncDisclosure();
  }
  private toggle(): void {
    const update = (): void => {
      this.expanded = !this.expanded;
      this.disclosures.set(this.message.turnKey + '|' + this.message.id, this.expanded);
    };
    NativeMotion.animate(this.getUIContext(), 'micro', update);
  }
  @Builder
  private members() {
    Column({ space: 2 }) {
      ForEach(this.message.children, (child: NativeMessage) => {
        if (child.role === 'tool') { NativeToolCallView({ client: this.client, sessionId: this.sessionId, message: child, disclosures: this.disclosures }) }
        else if (child.role === 'reasoning') { NativeMessageView({ client: this.client, sessionId: this.sessionId, message: child,
          preview: this.message.preview, runningReasoning: !this.message.closed, disclosures: this.disclosures }) }
        else { Text(child.label).fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91') }
      }, (child: NativeMessage) => child.id)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    Column({ space: this.expanded && !this.message.flat ? 8 : 0 }) {
      if (!this.message.flat) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          DSHIcon({ glyph: nativeProcessIcon(this.message.toolName), color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 14 })
          Text(this.headline).fontSize(12).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.dark ? '#CFD3D6' : '#61666B')
          DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 })
            .rotate({ angle: this.expanded ? -90 : 180 })
        }.width('100%')
      }.height(30).width('100%').padding({ left: 2, right: 2 }).backgroundColor(Color.Transparent)
        .onClick(() => { this.toggle(); })
      }
      if (this.message.flat) { this.members() }
      else if (this.expanded) {
        this.members()
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
