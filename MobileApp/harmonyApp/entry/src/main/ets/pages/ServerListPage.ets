import { ServerConfig } from '../core/TermirrorCore';

/**
 * 服务器列表页，对齐蓝本 App.kt 的 ServerListScreen + Header + ServerRow：
 * banner 图 + “服务器列表”标题 + 圆形主色加号按钮；Card 列表行；底部“网络诊断”入口。
 */
@Component
export struct ServerListPage {
  /** 服务器列表（由父组件 Index 持有并刷新）。 */
  @Prop servers: ServerConfig[];
  onOpenLocal: () => void = () => {
  };
  onAdd: () => void = () => {
  };
  onOpen: (server: ServerConfig) => void = (server: ServerConfig) => {
  };
  onEdit: (server: ServerConfig) => void = (server: ServerConfig) => {
  };
  onCopy: (server: ServerConfig) => void = (server: ServerConfig) => {
  };
  onDelete: (server: ServerConfig) => void = (server: ServerConfig) => {
  };
  onReorder: (from: number, to: number) => void = (from: number, to: number) => {
  };
  onOpenSettings: () => void = () => {
  };

  private summaryOf(server: ServerConfig): string {
    return `${server.username}@${server.host}:${server.port}`;
  }

  /** 行右侧操作图标容器。 */
  @Builder
  ActionIcon(content: string, fontSize: number, onClick: () => void) {
    Column() {
      Text(content)
        .fontSize(fontSize)
        .textAlign(TextAlign.Center)
    }
    .justifyContent(FlexAlign.Center)
    .width(40)
    .height(46)
    .onClick(onClick)
  }

  /** 复用原彩色剪贴板图标并错位叠加，保留与其他操作一致的点击热区。 */
  @Builder
  CopyActionIcon(onClick: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      Text('📋')
        .fontSize(17)
        .textAlign(TextAlign.Center)
        .translate({ x: 3, y: -3 })
      Text('📋')
        .fontSize(17)
        .textAlign(TextAlign.Center)
        .translate({ x: -3, y: 3 })
    }
    .width(40)
    .height(46)
    .onClick(onClick)
  }

  /** 设置齿轮图标：使用系统符号 gearshape，与系统 UI 风格一致。 */
  @Builder
  GearIcon() {
    SymbolGlyph($r('sys.symbol.gearshape'))
      .fontSize(24)
      .fontColor([$r('sys.color.ohos_id_color_primary')])
  }

  build() {
    Stack() {
      Column() {
        // 头部：banner + 标题 + 加号按钮
        Row() {
          Column() {
            Image($rawfile('attach_banner.png'))
              .width(144)
              .height(72)
              .objectFit(ImageFit.Contain)
              .objectRepeat(ImageRepeat.NoRepeat)
              .align(Alignment.Start)
            Text('服务器列表')
              .fontSize(14)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          // 圆形主色加号按钮（十字用两个色块拼出，对齐蓝本 AddIcon）
          Stack() {
            Column().width(20).height(3).borderRadius(2).backgroundColor(Color.White)
            Column().width(3).height(20).borderRadius(2).backgroundColor(Color.White)
          }
          .width(42)
          .height(42)
          .borderRadius(21)
          .backgroundColor($r('sys.color.ohos_id_color_primary'))
          .onClick(() => this.onAdd())
        }
        .width('100%')

        // 服务器列表
        List({ space: 0 }) {
          ForEach(this.servers, (server: ServerConfig, index: number) => {
            ListItem() {
              Column() {
                Row() {
                  Column() {
                    Text(server.name.length > 0 ? server.name : server.host)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                    Text(this.summaryOf(server))
                      .fontSize(12)
                      .fontColor('#66182431')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .onClick(() => this.onOpen(server))

                  Row() {
                    this.ActionIcon('✏️', 20, () => this.onEdit(server))
                    this.CopyActionIcon(() => this.onCopy(server))
                    this.ActionIcon('🗑️', 20, () => this.onDelete(server))
                  }
                }
                .width('100%')
                .padding({ left: 16, top: 16, right: 10, bottom: 16 })
                .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
                .borderRadius(12)

                // 列表项之间分隔线（最后一项不画）
                if (index < this.servers.length - 1) {
                  Divider()
                    .color('#F0F1F3')
                    .strokeWidth(0.5)
                    .margin({ left: 16, top: 4 })
                }
              }
            }
          // key 必须包含全部可变字段：同名编辑后若仍用 server.name 作 key，
          // ForEach 复用旧组件导致列表显示与传回 onEdit/onOpen 的数据都是旧的
          }, (server: ServerConfig) => `${server.name}\n${server.username}\n${server.host}\n${server.port}\n${server.password}`)
            .onMove((from: number, to: number) => {
              this.onReorder(from, to);
            })
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 16 })

        // 底部：左侧“网络诊断”入口（蓝本的 LOCAL 页在鸿蒙上是网络诊断），
        // 右侧设置按钮，二者同一行水平对齐
        Row() {
          Button('网络诊断')
            .backgroundColor(Color.Transparent)
            .fontColor($r('sys.color.ohos_id_color_primary'))
            .onClick(() => this.onOpenLocal())

          Blank()

          Stack({ alignContent: Alignment.Center }) {
            this.GearIcon()
          }
          .width(42)
          .height(42)
          .onClick(() => this.onOpenSettings())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
