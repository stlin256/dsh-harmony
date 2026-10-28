import { NativeExperience } from '../services/NativeExperience';
import { NativeMessage, NativeTextBlock } from '../services/NativeSessionModel';

@Component
export struct NativeMessageView {
  onCompatibility: () => void = (): void => {};
  @Prop message: NativeMessage = new NativeMessage();
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private reasoningOpen: boolean = false;
  @State private toolOpen: boolean = false;

  private animate(action: () => void): void {
    if (NativeExperience.reducedMotion()) action();
    else this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, action);
  }

  build() {
    Column({ space: 10 }) {
      Text(this.message.label).fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor(this.dark ? '#CFD3D6' : '#61666B')
      if (this.message.reasoning) {
        Button(this.reasoningOpen ? '收起思考过程' : '查看思考过程', { type: ButtonType.Normal })
          .height(44).fontSize(12).borderRadius(12)
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .onClick(() => { this.animate(() => { this.reasoningOpen = !this.reasoningOpen; }); })
        if (this.reasoningOpen) {
          Text(this.message.reasoning).fontSize(13).lineHeight('21fp').copyOption(CopyOptions.InApp)
            .fontColor(this.dark ? '#CFD3D6' : '#61666B')
        }
      }
      if (this.message.role === 'tool') {
        Button(this.toolOpen ? '收起执行详情' : '查看执行详情', { type: ButtonType.Normal })
          .height(44).fontSize(12).borderRadius(12).backgroundColor(Color.Transparent)
          .fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .onClick(() => { this.animate(() => { this.toolOpen = !this.toolOpen; }); })
      }
      if (this.message.role !== 'tool' || this.toolOpen) {
        ForEach(this.message.blocks, (block: NativeTextBlock) => {
          if (block.kind === 'code') {
            Column({ space: 8 }) {
              Text(block.language || '代码').fontSize(11).fontColor(this.dark ? '#CFD3D6' : '#61666B')
              Text(block.text).fontFamily('monospace').fontSize(12).lineHeight('20fp')
                .copyOption(CopyOptions.InApp).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
            }.padding(12).width('100%').alignItems(HorizontalAlign.Start)
              .borderRadius(12).backgroundColor(this.dark ? '#353638' : '#F5F6F7')
          } else if (block.kind === 'heading') {
            Text(block.text).fontSize(18).lineHeight('28fp').fontWeight(FontWeight.Medium)
              .copyOption(CopyOptions.InApp).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          } else if (block.kind === 'quote') {
            Text(block.text).fontSize(13).lineHeight('22fp').padding(12).borderRadius(12)
              .backgroundColor(this.dark ? '#353638' : '#F5F6F7')
              .copyOption(CopyOptions.InApp).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          } else {
            Text(block.text).fontSize(14).lineHeight('23fp').copyOption(CopyOptions.InApp)
              .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          }
        }, (_block: NativeTextBlock, index: number) => index.toString())
      } else {
        Text(this.message.text).fontSize(12).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.dark ? '#CFD3D6' : '#61666B')
      }
      if (this.message.role === 'notice') {
        Button('在兼容模式中处理', { type: ButtonType.Normal }).height(44).fontSize(12).borderRadius(12)
          .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onClick(this.onCompatibility)
      }
      if (!this.message.text && !this.message.reasoning) {
        Text('此消息包含高级内容，请在兼容模式查看。').fontSize(13)
          .fontColor(this.dark ? '#CFD3D6' : '#61666B')
      }
    }.alignItems(HorizontalAlign.Start).width('100%')
      .padding(this.message.role === 'user' || this.message.role === 'tool' ? 16 : 4)
      .backgroundColor(this.message.role === 'user' || this.message.role === 'tool' ? this.dark ? '#2C2C2E' : '#F5F6F7' : Color.Transparent)
      .borderRadius(16)
  }
}
