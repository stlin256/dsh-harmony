import { pasteboard } from '@kit.BasicServicesKit';
import { NativeTextSource } from '../services/NativeTextSource';
import { NativeInlineText } from './NativeInlineText';

/** Full text is retained. Very long bodies open a virtualised native reader. */
@Component
export struct NativeTextContent {
  @Prop @Watch('changed') text: string = '';
  @Prop monospace: boolean = false;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private reading: boolean = false;
  @State private copied: boolean = false;
  private source: NativeTextSource = new NativeTextSource();
  aboutToAppear(): void { this.changed(); }
  private changed(): void { this.source.set(this.text); }
  @Builder
  private body(value: string) {
    if (this.monospace) {
      Text(value).width('100%').fontSize(12).lineHeight('22fp')
        .fontFamily('Noto Sans Mono, monospace').copyOption(CopyOptions.InApp)
        .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
    } else {
      NativeInlineText({ text: value })
    }
  }
  @Builder
  private reader() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('完整内容').fontSize(16).layoutWeight(1).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        Button(this.copied ? '已复制' : '复制全文').height(44).onClick(() => {
          pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.text))
            .then(() => { this.copied = true; }).catch(() => { this.copied = false; });
        })
        Button('返回').height(44).onClick(() => { this.reading = false; })
      }.width('100%')
      List() {
        LazyForEach(this.source, (part: string) => {
          ListItem() {
            this.body(part)
          }
        }, (_part: string, index: number) => index.toString())
      }.layoutWeight(1).width('100%').cachedCount(4)
    }.padding(16).width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
  }
  build() {
    Column({ space: 8 }) {
      this.body(this.text.length > 8192 ? this.source.getData(0) : this.text)
      if (this.text.length > 8192) {
        Button('阅读全文 · ' + this.text.length + ' 字符').height(44).onClick(() => { this.reading = true; this.copied = false; })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .bindContentCover(this.reading, this.reader, { modalTransition: ModalTransition.DEFAULT, onDisappear: (): void => { this.reading = false; } })
  }
}
