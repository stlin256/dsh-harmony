import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeMessage } from '../services/NativeSessionModel';
import { DSHIcon } from './DSHIcon';
import { NativeMotion } from '../services/NativeMotion';
import { NativeProcessStepView } from './NativeProcessStepView';
import { NativeListSource } from '../services/NativeListSource';

/** Turn-level process disclosure containing direct operation rows. */
@Component
export struct NativeProcessView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  disclosures: Map<string, boolean> = new Map<string, boolean>();
  @Prop @Watch('changed') message: NativeMessage = new NativeMessage();
  @Prop maxExpandedHeight: number = 240;
  @Prop maxChildExpandedHeight: number = 160;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private expanded: boolean = false;
  private disclosureId: string = '';
  private flatApplied: boolean = false;
  private source: NativeListSource<NativeMessage> = new NativeListSource<NativeMessage>();

  aboutToAppear(): void {
    this.flatApplied = this.message.flat;
    this.expanded = this.message.flat ||
      this.disclosures.get(this.message.turnKey + '|' + this.message.id) === true;
    this.changed();
  }

  private changed(): void {
    this.source.set(this.message.children, (child: NativeMessage): string => child.id);
    const key = this.message.turnKey + '|' + this.message.id;
    if (key !== this.disclosureId) {
      this.disclosureId = key;
      this.flatApplied = this.message.flat;
      this.expanded = this.message.flat || this.disclosures.get(key) === true;
    } else if (this.flatApplied !== this.message.flat) {
      this.flatApplied = this.message.flat;
      this.expanded = this.message.flat || this.disclosures.get(key) === true;
    }
  }

  private toggle(): void {
    NativeMotion.animate(this.getUIContext(), 'micro', (): void => {
      this.expanded = !this.expanded;
      this.disclosures.set(this.disclosureId, this.expanded);
    });
  }

  @Builder
  private members() {
    List({ space: 2 }) {
      LazyForEach(this.source, (child: NativeMessage) => {
        ListItem() {
          NativeProcessStepView({ client: this.client, sessionId: this.sessionId, message: child,
            disclosures: this.disclosures, maxExpandedHeight: this.maxChildExpandedHeight })
        }
      }, (child: NativeMessage) => child.id)
    }.width('100%').padding({ right: 10 })
      .constraintSize({ maxHeight: Math.max(96, this.maxExpandedHeight) })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .cachedCount(4)
      .transition(NativeMotion.rowTransition())
  }

  build() {
    Column({ space: this.expanded ? 6 : 0 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 4 }) {
          DSHIcon({ glyph: 'think-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 14 })
          Text('工作过程').fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#CFD3D6' : '#61666B')
          if (this.message.detail) {
            Text('·').fontSize(12).fontColor(this.dark ? '#777A80' : '#A1A4A9')
            Text(this.message.detail).fontSize(12).layoutWeight(1).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
              .opacity(this.expanded ? 0 : 1)
              .animation(NativeMotion.implicit('micro'))
          } else {
            Blank().layoutWeight(1)
          }
          DSHIcon({ glyph: 'chevron-left-outline',
            color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 })
            .rotate({ angle: this.expanded ? -90 : 180 })
            .animation(NativeMotion.implicit('micro'))
        }.width('100%')
      }.height(30).width('100%').padding({ left: 2, right: 2 })
        .backgroundColor(Color.Transparent).onClick((): void => { this.toggle(); })
      if (this.expanded) { this.members() }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
