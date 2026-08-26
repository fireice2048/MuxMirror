import { ServerConfig } from '../core/TermirrorCore';

/** 输入框左侧标签统一宽度（vp），保证所有编辑框左缘对齐。 */
const LABEL_WIDTH: number = 48;

/**
 * 服务器新增/编辑弹窗，对齐蓝本 App.kt 的 ServerDialog：
 * 名称/地址/端口/用户/密码 5 个输入框，密码可见性切换，地址+用户非空才可保存。
 */
@CustomDialog
export struct ServerEditDialog {
  controller: CustomDialogController;
  /** 传入 null 表示新增。 */
  server: ServerConfig | null = null;
  onSave: (config: ServerConfig) => void = () => {
  };

  @State name: string = '';
  @State host: string = '';
  @State port: string = '22';
  @State username: string = '';
  @State password: string = '';
  @State passwordVisible: boolean = false;

  aboutToAppear(): void {
    if (this.server !== null) {
      this.name = this.server.name;
      this.host = this.server.host;
      this.port = this.server.port.toString();
      this.username = this.server.username;
      this.password = this.server.password;
    }
  }

  /** 保存校验：地址与用户名非空，对齐蓝本 enabled 条件。 */
  private canSave(): boolean {
    return this.host.trim().length > 0 && this.username.trim().length > 0;
  }

  private doSave(): void {
    const portNum = parseInt(this.port);
    this.onSave({
      name: this.name,
      host: this.host,
      port: isNaN(portNum) ? 22 : portNum,
      username: this.username,
      password: this.password,
    });
    this.controller.close();
  }

  build() {
    Column({ space: 12 }) {
      Text(this.server === null ? '新增服务器' : '编辑服务器')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)

      Scroll() {
        Column({ space: 8 }) {
          // 每个输入框左侧加文本 Label，统一标签宽度保证所有编辑框对齐（人工验收反馈）
          Row() {
            Text('名称')
              .fontSize(14)
              .fontColor('#66182431')
              .width(LABEL_WIDTH)
            TextInput({ placeholder: '名称', text: this.name })
              .layoutWeight(1)
              .onChange((value: string) => this.name = value)
          }
          .width('100%')

          Row() {
            Text('地址')
              .fontSize(14)
              .fontColor('#66182431')
              .width(LABEL_WIDTH)
            TextInput({ placeholder: '地址', text: this.host })
              .layoutWeight(1)
              .onChange((value: string) => this.host = value)
          }
          .width('100%')

          Row() {
            Text('端口')
              .fontSize(14)
              .fontColor('#66182431')
              .width(LABEL_WIDTH)
            TextInput({ placeholder: '端口', text: this.port })
              .layoutWeight(1)
              .type(InputType.Number)
              .onChange((value: string) => {
                // 仅保留数字，对齐蓝本的端口过滤逻辑
                const digits = value.split('').filter((ch: string) => ch >= '0' && ch <= '9').join('');
                this.port = digits;
              })
          }
          .width('100%')

          Row() {
            Text('用户')
              .fontSize(14)
              .fontColor('#66182431')
              .width(LABEL_WIDTH)
            TextInput({ placeholder: '用户', text: this.username })
              .layoutWeight(1)
              .onChange((value: string) => this.username = value)
          }
          .width('100%')

          Row() {
            Text('密码')
              .fontSize(14)
              .fontColor('#66182431')
              .width(LABEL_WIDTH)
            TextInput({ placeholder: '密码', text: this.password })
              .type(this.passwordVisible ? InputType.Normal : InputType.Password)
              .layoutWeight(1)
              .onChange((value: string) => this.password = value)
            // 密码可见性切换，对齐蓝本的 👁 / 🙈
            Text(this.passwordVisible ? '👁' : '🙈')
              .fontSize(18)
              .width(40)
              .textAlign(TextAlign.Center)
              .onClick(() => this.passwordVisible = !this.passwordVisible)
          }
          .width('100%')
        }
        .width('100%')
      }
      .scrollBar(BarState.Auto)
      .constraintSize({ maxHeight: 320 })

      // 按钮与输入框间距加大到 2 倍（12→24vp），防止误点（人工验收反馈）
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor('#F1F3F5')
          .fontColor('#182431')
          .onClick(() => this.controller.close())
        Button('保存')
          .layoutWeight(1)
          .enabled(this.canSave())
          .onClick(() => this.doSave())
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    // customStyle 弹窗默认背景透明，补白底圆角，否则内容看不清（人工验收反馈）
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}
