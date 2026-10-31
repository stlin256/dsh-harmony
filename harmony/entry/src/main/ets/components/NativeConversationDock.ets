/**
 * Reusable top conversation dock. New plan-like controls can be composed into
 * the builder instead of creating independent absolute-position rules.
 */
@Component
export struct NativeConversationDock {
  @BuilderParam content: () => void;

  build() {
    Column({ space: 4 }) {
      this.content()
    }.width('100%').alignItems(HorizontalAlign.Center)
      .padding({ left: 12, right: 12 })
      .accessibilityGroup(true)
  }
}
