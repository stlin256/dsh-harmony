import { ColorMetrics } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';

/**
 * DSH product glyphs adapted from deepseek-ai/deepseek-harness's
 * packages/client/ui-primitives/src/icons/artwork.ts (MIT).
 * DSH path coordinates are CSS px; Harmony Path commands use physical px,
 * so scale coordinates by the device's px-per-vp ratio before drawing.
 */
@Component
export struct DSHIcon {
  @Prop glyph: string = 'plus-outline';
  @Prop color: ResourceColor = '#F9FAFB';
  @Prop glyphSize: number = 16;
  @StorageLink('nativeDark') private dark: boolean = false;

  private pathForGlyph(): string {
    switch (this.glyph) {
      case 'new-chat-outline': return 'M2.37091 11.2501C1.58745 9.89288 1.32067 8.29835 1.61969 6.76006C1.91872 5.22177 2.76342 3.8433 3.99826 2.87846C5.2331 1.91362 6.77494 1.42737 8.33988 1.50925C9.90482 1.59113 11.3875 2.23562 12.5149 3.32406C13.6425 4.41269 14.3387 5.87206 14.4754 7.4334C14.612 8.99474 14.18 10.5529 13.2587 11.8209C12.3375 13.0888 10.9891 13.9813 9.46194 14.3337C8.18691 14.628 6.85895 14.5294 5.64989 14.0605C5.1712 13.8748 4.76962 13.4932 4.26534 13.3967C3.67413 13.2835 2.95257 13.5598 2.03794 14.3337 M8 5V11 M5 8H11';
      case 'settings-outline': return 'M8 9.75012C8.9665 9.75012 9.75 8.96662 9.75 8.00012C9.75 7.03362 8.9665 6.25012 8 6.25012C7.0335 6.25012 6.25 7.03362 6.25 8.00012C6.25 8.96662 7.0335 9.75012 8 9.75012Z M13.0107 7.79377C12.9505 7.89401 12.9205 7.94413 12.9205 7.99951C12.9205 8.0549 12.9505 8.10502 13.0106 8.20528L13.9849 9.83006C14.045 9.93029 14.0751 9.9804 14.0751 10.0358C14.0751 10.0911 14.045 10.1413 13.9849 10.2415L13.0037 11.8777C12.9468 11.9726 12.9184 12.0201 12.8725 12.0461C12.8267 12.072 12.7713 12.072 12.6607 12.072H10.6704C10.5598 12.072 10.5045 12.072 10.4586 12.098C10.4128 12.1239 10.3843 12.1714 10.3274 12.2662L9.33825 13.9142C9.28133 14.009 9.25287 14.0564 9.20703 14.0823C9.16118 14.1083 9.10588 14.1083 8.99529 14.1083H7.00486C6.89426 14.1083 6.83896 14.1083 6.79312 14.0823C6.74727 14.0564 6.71881 14.009 6.6619 13.9142L5.67273 12.2662C5.61581 12.1714 5.58735 12.1239 5.54151 12.098C5.49566 12.072 5.44036 12.072 5.32977 12.072H3.33945C3.2288 12.072 3.17347 12.072 3.12761 12.0461C3.08176 12.0201 3.0533 11.9726 2.9964 11.8777L2.0152 10.2415C1.9551 10.1413 1.92505 10.0911 1.92505 10.0358C1.92505 9.9804 1.9551 9.93029 2.0152 9.83006L2.98951 8.20528C3.04963 8.10502 3.07969 8.0549 3.07969 7.99951C3.07968 7.94413 3.04961 7.89401 2.98946 7.79377L2.01529 6.17011C1.95514 6.06987 1.92507 6.01975 1.92507 5.96437C1.92506 5.90899 1.95512 5.85886 2.01524 5.7586L2.9964 4.1224C3.0533 4.0275 3.08176 3.98005 3.12761 3.95408C3.17347 3.92811 3.2288 3.92811 3.33945 3.92811H5.32977C5.44036 3.92811 5.49566 3.92811 5.54151 3.90216C5.58735 3.87621 5.61581 3.82879 5.67273 3.73397L6.6619 2.08599C6.71881 1.99116 6.74727 1.94375 6.79312 1.9178C6.83896 1.89185 6.89426 1.89185 7.00486 1.89185H8.99529C9.10588 1.89185 9.16118 1.89185 9.20703 1.9178C9.25287 1.94375 9.28133 1.99116 9.33825 2.08599L10.3274 3.73397C10.3843 3.82879 10.4128 3.87621 10.4586 3.90216C10.5045 3.92811 10.5598 3.92811 10.6704 3.92811H12.6607C12.7713 3.92811 12.8267 3.92811 12.8725 3.95408C12.9184 3.98005 12.9468 4.0275 13.0037 4.1224L13.9849 5.7586C14.045 5.85886 14.0751 5.90899 14.0751 5.96437C14.0751 6.01975 14.045 6.06987 13.9849 6.17011L13.0107 7.79377Z';
      case 'panel-left-outline': return 'M13.5 1.5H2.5C1.94772 1.5 1.5 1.94772 1.5 2.5V13.5C1.5 14.0523 1.94772 14.5 2.5 14.5H13.5C14.0523 14.5 14.5 14.0523 14.5 13.5V2.5C14.5 1.94772 14.0523 1.5 13.5 1.5Z M5.5 1.5V14.5';
      case 'chevron-left-outline': return 'M10 4L6.70711 7.29289C6.31658 7.68342 6.31658 8.31658 6.70711 8.70711L10 12';
      case 'ellipsis-outline': return 'M3 9C3.55228 9 4 8.55228 4 8C4 7.44772 3.55228 7 3 7C2.44772 7 2 7.44772 2 8C2 8.55228 2.44772 9 3 9Z M8 9C8.55228 9 9 8.55228 9 8C9 7.44772 8.55228 7 8 7C7.44772 7 7 7.44772 7 8C7 8.55228 7.44772 9 8 9Z M13 9C13.5523 9 14 8.55228 14 8C14 7.44772 13.5523 7 13 7C12.4477 7 12 7.44772 12 8C12 8.55228 12.4477 9 13 9Z';
      case 'plus-outline': return 'M8 2V14 M2 8H14';
      case 'image-outline': return 'M2.25 2.75H13.75V13.25H2.25V2.75Z M2.5 11L6 7.5L8.5 10L10.5 8L13.5 11 M10.75 5.25C11.1642 5.25 11.5 5.58579 11.5 6C11.5 6.41421 11.1642 6.75 10.75 6.75C10.3358 6.75 10 6.41421 10 6C10 5.58579 10.3358 5.25 10.75 5.25Z';
      case 'file-outline': return 'M3 1.75H9.5L13 5.25V14.25H3V1.75Z M9.5 1.75V5.25H13 M5.5 8H10.5 M5.5 10.75H10.5';
      case 'drag-handle-outline': return 'M4 5H12 M4 8H12 M4 11H12';
      case 'paperclip-outline': return 'M12.75 4.5V9.5C12.75 10.7598 12.2496 11.968 11.3588 12.8588C10.468 13.7496 9.25978 14.25 8 14.25C6.74022 14.25 5.53204 13.7496 4.64124 12.8588C3.75045 11.968 3.25 10.7598 3.25 9.5V5C3.25 4.13805 3.59241 3.3114 4.2019 2.7019C4.8114 2.09241 5.63805 1.75 6.5 1.75C7.36195 1.75 8.1886 2.09241 8.7981 2.7019C9.40759 3.3114 9.75 4.13805 9.75 5V9.5C9.75 9.96413 9.56563 10.4092 9.23744 10.7374C8.90925 11.0656 8.46413 11.25 8 11.25C7.53587 11.25 7.09075 11.0656 6.76256 10.7374C6.43437 10.4092 6.25 9.96413 6.25 9.5V5.5';
      case 'queue-outline': return 'M5 6.75H11 M5 9H8 M2.37067 11.2497C1.5872 9.89252 1.32042 8.29798 1.61945 6.7597C1.91847 5.22141 2.76317 3.84293 3.99801 2.87809C5.23285 1.91325 6.7747 1.427 8.33964 1.50888C9.90458 1.59076 11.3873 2.23526 12.5147 3.32369C13.6422 4.41232 14.3384 5.8717 14.4751 7.43304C14.6118 8.99438 14.1797 10.5525 13.2585 11.8205C12.3372 13.0885 10.9889 13.9809 9.4617 14.3334C8.18666 14.6277 6.8587 14.529 5.64964 14.0601C5.17095 13.8745 4.76937 13.4929 4.26509 13.3963C3.67389 13.2832 2.95232 13.5595 2.0377 14.3334';
      case 'paper-plane-outline': return 'M4.74024 9.11029L1.82882 7.79865C1.75022 7.76323 1.75026 7.65161 1.82889 7.61626L12.9665 2.60943C13.0354 2.57846 13.1125 2.63213 13.1073 2.70749L12.3914 13.1388C12.3864 13.2117 12.3073 13.2548 12.2433 13.2194L6.12677 9.83657 M8.44336 11.0825L6.2832 13.2843C6.22048 13.3482 6.11182 13.3038 6.11182 13.2143V9.86772C6.11182 9.84165 6.122 9.8166 6.1402 9.79793L12.972 2.78748';
      case 'stop-fill': return 'M12.5 2.5H3.5C2.94772 2.5 2.5 2.94772 2.5 3.5V12.5C2.5 13.0523 2.94772 13.5 3.5 13.5H12.5C13.0523 13.5 13.5 13.0523 13.5 12.5V3.5C13.5 2.94772 13.0523 2.5 12.5 2.5Z';
      case 'check-outline': return 'M2.25 8.5L5.49732 11.7473C5.90519 12.1552 6.57263 12.1344 6.95426 11.7018L13.75 4';
      case 'send-arrow': return 'M8.3125 0.980183C8.66767 1.0531 8.97902 1.20418 9.2627 1.43233C9.48724 1.61297 9.73029 1.85793 9.97949 2.10714L14.707 6.83468L13.293 8.24874L9 3.95577V15.0417H7V3.95577L2.70703 8.24874L1.29297 6.83468L6.02051 2.10714C6.26971 1.85793 6.51277 1.61297 6.7373 1.43233C6.97662 1.23986 7.28445 1.04402 7.6875 0.980183C7.8973 0.947006 8.1031 0.95516 8.3125 0.980183Z';
      case 'copy-outline': return 'M3.52075 4.07373H9.91395C11.0185 4.07373 11.91395 4.96916 11.91395 6.07373V12.46693C11.91395 13.5715 11.0185 14.46693 9.91395 14.46693H3.52075C2.41618 14.46693 1.52075 13.5715 1.52075 12.46693V6.07373C1.52075 4.96916 2.41618 4.07373 3.52075 4.07373Z';
      default: return '';
    }
  }

  private scaleCommands(commands: string): string {
    const pxPerVp = this.getUIContext().vp2px(this.glyphSize / 16);
    return commands.replace(/-?(?:\d+\.?\d*|\.\d+)/g,
      (value: string) => (Number(value) * pxPerVp).toString());
  }

  private filledGlyph(): boolean {
    return this.glyph === 'ellipsis-outline' || this.glyph === 'send-arrow' || this.glyph === 'stop-fill';
  }
  /**
   * Parent @Prop values can be retained across a storage-linked theme change on
   * ArkUI custom components. Resolve the known semantic tokens here as well so
   * the glyph itself is guaranteed to repaint with the active surface.
   */
  private resolvedColor(color: ResourceColor, dark: boolean): ResourceColor {
    if (typeof color !== 'string') return color;
    const value = color.toUpperCase();
    if (['#F9FAFB', '#0F1115', '#17181B', '#202124', '#25262A', '#33353A', '#E7E7E9', '#F4F4F5'].includes(value)) {
      return dark ? '#F9FAFB' : '#17181B';
    }
    if (['#CFD3D6', '#93969B', '#8A8D91', '#777A80', '#A1A1AA', '#B5B8BD', '#61666B'].includes(value)) {
      return dark ? '#CFD3D6' : '#61666B';
    }
    if (['#8AB4FF', '#3964FE'].includes(value)) return dark ? '#8AB4FF' : '#3964FE';
    return color;
  }
  private tint(color: ResourceColor, dark: boolean): drawing.ColorFilter {
    let alpha = 255;
    let red = 255;
    let green = 255;
    let blue = 255;
    try {
      const value = ColorMetrics.resourceColor(this.resolvedColor(color, dark));
      alpha = value.alpha;
      red = value.red;
      green = value.green;
      blue = value.blue;
    } catch (_) {
      // Invalid or unavailable resources fall back to the active theme foreground.
      if (!dark) {
        red = 23;
        green = 24;
        blue = 27;
      }
    }
    return drawing.ColorFilter.createBlendModeColorFilter({
      alpha: alpha,
      red: red,
      green: green,
      blue: blue
    }, drawing.BlendMode.SRC_IN);
  }
  build() {
    if (['think-outline', 'browse-outline', 'folder-outline', 'search-outline', 'edit-outline', 'api-outline', 'code-outline', 'eye-outline', 'globe-outline', 'agent-preset-outline', 'plan-outline', 'question-outline', 'sparkle', 'pin-outline', 'pin-fill', 'branch-outline', 'archive-outline', 'download-outline', 'close-outline', 'light-outline', 'dark-outline', 'followsystem-outline', 'personalization-outline', 'deepseek-logo'].includes(this.glyph)) {
      Stack() {
        Image($rawfile('dsh-icons/' + this.glyph + '.svg')).width(this.glyphSize).height(this.glyphSize)
          .objectFit(ImageFit.Contain)
          .supportSvg2(true)
          .colorFilter(this.tint(this.color, this.dark))
      }.width(this.glyphSize).height(this.glyphSize)
    } else if (this.glyph === 'copy-outline') {
      Stack() {
        Path({ commands: this.scaleCommands(this.pathForGlyph()), width: 16, height: 16 })
          .fill(Color.Transparent).stroke(this.resolvedColor(this.color, this.dark)).strokeWidth(1)
          .width(this.glyphSize).height(this.glyphSize)
        Path({ commands: this.scaleCommands('M11.9792 1.53296C13.36 1.53296 14.4792 2.65225 14.4792 4.03296V9.42847C14.4792 10.3756 13.9521 11.1987 13.1755 11.6228V10.3298C13.3652 10.0787 13.4792 9.7674 13.4792 9.42847V4.03296C13.4792 3.20453 12.8077 2.53296 11.9792 2.53296H6.58374C6.27966 2.53301 5.99684 2.6235 5.7605 2.77905H4.42358C4.85652 2.03463 5.66056 1.53304 6.58374 1.53296H11.9792Z'), width: 16, height: 16 })
          .fill(this.resolvedColor(this.color, this.dark)).stroke(this.resolvedColor(this.color, this.dark)).strokeWidth(0)
          .width(this.glyphSize).height(this.glyphSize)
      }.width(this.glyphSize).height(this.glyphSize)
    } else {
      Path({ commands: this.scaleCommands(this.pathForGlyph()), width: 16, height: 16 })
        .fill(this.filledGlyph() ? this.resolvedColor(this.color, this.dark) : Color.Transparent)
        .stroke(this.resolvedColor(this.color, this.dark)).strokeWidth(this.filledGlyph() ? 0 : this.glyph === 'plus-outline' ? 1.3 : 1)
        .strokeLineCap(LineCapStyle.Round).strokeLineJoin(LineJoinStyle.Round)
        .width(this.glyphSize).height(this.glyphSize)
    }
  }
}
