import { NativeMenuItem } from '../services/NativeNavigation';
import { DSHIcon } from './DSHIcon';
import { NativeExperience } from '../services/NativeExperience';
import { NativeMotion } from '../services/NativeMotion';

/** Official Menu geometry with a 44vp touch target, presented by the caller's anchored popup. */
@Component
export struct NativeActionMenu {
  @Prop items: NativeMenuItem[] = [];
  onSelect: (id: string) => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;

  build() {
    Column() {
      ForEach(this.items, (item: NativeMenuItem) => {
        if (item.separator) { Divider().strokeWidth(0.5).color(this.dark ? '#53555B' : '#DADDE2').margin({ top: 3, bottom: 3, left: 2, right: 2 }) }
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            DSHIcon({ glyph: item.icon, glyphSize: 14, color: item.danger ? '#D84A4A' : this.dark ? '#E7E7E9' : '#25262A' })
            Text(item.title).fontSize(13).maxLines(1).layoutWeight(1)
              .fontColor(item.danger ? '#D84A4A' : this.dark ? '#F9FAFB' : '#17181B')
          }.width('100%')
        }.width('100%').height(44).borderRadius(12).padding({ left: 8, right: 8 })
          .backgroundColor(Color.Transparent).enabled(!item.disabled).opacity(item.disabled ? 0.4 : 1)
          .accessibilityText(item.title).onClick(() => { this.onSelect(item.id); })
      }, (item: NativeMenuItem) => item.id)
    }.width(208).padding(4).borderRadius(16)
      .transition(NativeMotion.overlayTransition())
  }
}
