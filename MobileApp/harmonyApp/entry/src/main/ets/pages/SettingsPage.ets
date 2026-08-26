import { setMuxGroupingMode, GROUPING_WINDOW, GROUPING_DIRECTORY } from '../core/SettingsStore';

/**
 * 设置页面。
 * 目前只承载「MUX 导航标签页分组方式」。
 */
@Component
export struct SettingsPage {
  onBack: () => void = () => {
  };

  @StorageProp('muxGroupingMode') groupingMode: string = GROUPING_WINDOW;

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('✕')
          .fontSize(18)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => this.onBack())
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank()
          .width(36)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })

      // 分组方式选项
      Column({ space: 0 }) {
        this.OptionRow('按窗口分组', GROUPING_WINDOW)
        Divider().color('#F0F1F3').strokeWidth(0.5).margin({ left: 16 })
        this.OptionRow('按目录分组', GROUPING_DIRECTORY)
      }
      .width('100%')
      .margin({ top: 16 })
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
    .padding({ left: 16, right: 16, bottom: 16 })
  }

  @Builder
  OptionRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor('#182431')
        .layoutWeight(1)

      if (this.groupingMode === value) {
        Text('✓')
          .fontSize(18)
          .fontColor($r('sys.color.ohos_id_color_primary'))
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      const context = getContext(this);
      setMuxGroupingMode(context, value);
    })
  }
}
