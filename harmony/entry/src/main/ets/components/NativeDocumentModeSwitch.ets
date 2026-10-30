import { DSHIcon } from './DSHIcon';
import { NativeMotion } from '../services/NativeMotion';

/** Compact preview/source switch for SVG and Markdown workspace documents. */
@Component
export struct NativeDocumentModeSwitch {
  @Prop mode: string = 'preview';
  onMode: (mode: string) => void = (_mode: string): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;

  private select(mode: string): void {
    if (mode !== this.mode) this.onMode(mode);
  }

  private iconColor(selected: boolean): ResourceColor {
    if (selected) return this.dark ? '#101216' : '#FFFFFF';
    return this.dark ? '#93969B' : '#777A80';
  }

  @Builder
  private modeButton(mode: string, glyph: string, label: string) {
    Button({ type: ButtonType.Normal }) {
      DSHIcon({ glyph: glyph, glyphSize: 14, color: this.iconColor(this.mode === mode) })
    }.width(34).height(26).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
      .accessibilityText(label)
      .onClick((): void => { this.select(mode); })
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width(34).height(26).borderRadius(8)
        .backgroundColor(this.dark ? '#B8CFFF' : '#254DAB')
        .translate({ x: this.mode === 'preview' ? 2 : 40 })
        .animation(NativeMotion.implicit('micro'))
      Row({ space: 4 }) {
        this.modeButton('preview', 'eye-outline', '预览')
        this.modeButton('code', 'code-outline', '代码')
      }.padding({ left: 2, right: 2 })
    }.width(76).height(32).padding(0).borderRadius(10)
      .backgroundColor(this.dark ? '#2C2D31' : '#F0F2F5')
      .border({ width: 0.5, color: this.dark ? '#3B3D42' : '#E0E3E8' })
      .clip(true)
  }
}
