import { tcpCheck, TmEvent, tmEventSignal } from '../core/TermirrorCore';
import { EventSignalCancellableSet } from '../utilities/communication/EventSignal';

const TERMINAL_GREEN: string = '#B7F7C1';

/**
 * 网络诊断页（蓝本 LocalTerminalScreen 在鸿蒙上的形态）：
 * 黑底绿字输出（支持选中复制）+ 输入栏，支持 `tcp <IP/域名> [端口]` 连通性检测。
 */
@Component
export struct NetworkDiagPage {
  onBack: () => void = () => {
  };

  @State input: string = '';
  @State output: string = '网络诊断 已就绪。\n$ ';
  private scroller: Scroller = new Scroller();
  private eventCancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
  private diagListener: (ev: TmEvent) => void = (ev: TmEvent) => {
    if (ev.type === 'diag' && ev.sessionId === 0) {
      this.appendOutput(ev.data ?? '');
    }
  };

  aboutToAppear(): void {
    this.eventCancellables.cancelAll();
    tmEventSignal.on(this.diagListener).into(this.eventCancellables);
  }

  aboutToDisappear(): void {
    this.eventCancellables.cancelAll();
  }

  private appendOutput(text: string): void {
    this.output += `${text}\n$ `;
    this.scroller.scrollEdge(Edge.Bottom);
  }

  /** 解析并执行 tcp 命令，校验逻辑对齐蓝本 LocalTerminal.ohos.kt。 */
  private runCommand(command: string): void {
    if (command.trim().length === 0) {
      return;
    }
    this.output += `${command}\n`;
    const parts = command.trim().split(/\s+/).filter((s: string) => s.length > 0);
    if (parts.length < 2 || parts.length > 3 || parts[0].toLowerCase() !== 'tcp') {
      this.appendOutput('HarmonyOS 网络诊断仅支持 TCP 检测。\n用法：tcp <IP/域名> [端口]');
      return;
    }
    const host = parts[1];
    if (!this.isValidHost(host)) {
      this.appendOutput('目标地址必须是合法的 IP 地址或域名');
      return;
    }
    let port = 443;
    if (parts.length === 3) {
      const parsed = parseInt(parts[2]);
      if (isNaN(parsed)) {
        this.appendOutput('端口必须是 1 到 65535 之间的整数');
        return;
      }
      if (parsed < 1 || parsed > 65535) {
        this.appendOutput('端口必须在 1 到 65535 之间');
        return;
      }
      port = parsed;
    }
    // 结果经 type='diag' 事件异步返回（见 diagListener）
    tcpCheck(host, port);
  }

  /** 校验目标地址：IPv4 或合法域名（域名解析由底层 Rust 完成）。 */
  private isValidHost(host: string): boolean {
    return this.isIPv4(host) || this.isDomain(host);
  }

  private isDomain(host: string): boolean {
    if (host.length > 253) {
      return false;
    }
    return /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/.test(host);
  }

  private isIPv4(host: string): boolean {
    const octets = host.split('.');
    if (octets.length !== 4) {
      return false;
    }
    return octets.every((octet: string) => {
      if (octet.length === 0 || !/^\d+$/.test(octet)) {
        return false;
      }
      const value = parseInt(octet);
      return value >= 0 && value <= 255;
    });
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('网络诊断')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(TERMINAL_GREEN)
        Blank()
        Button('返回')
          .backgroundColor(Color.Transparent)
          .fontColor(TERMINAL_GREEN)
          .onClick(() => this.onBack())
      }
      .width('100%')

      // 输出区
      Scroll(this.scroller) {
        Text(this.output)
          .fontSize(12)
          .fontColor(TERMINAL_GREEN)
          .width('100%')
          .textAlign(TextAlign.Start)
          .copyOption(CopyOptions.InApp)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)

      // 输入栏：3 行文本框 + 圆形发送按钮，对齐蓝本 TerminalInputBar
      Row({ space: 8 }) {
        TextArea({ placeholder: 'tcp <IP/域名> [端口]，例如：\ntcp 192.168.1.1 80\ntcp baidu.com 443', text: this.input })
          .layoutWeight(1)
          .height(72)
          // 黑底页面下默认输入文字对比度不足（人工验收反馈），提亮为终端绿
          .fontColor(TERMINAL_GREEN)
          .backgroundColor('#1A1D24')
          .placeholderColor('#80808080')
          .onChange((value: string) => this.input = value)
        Column() {
          // 纸飞机发送图标（机头朝右上，青蓝色）：rawfile PNG，只设宽度保持原图比例
          Image($rawfile('ic_send_plane.png'))
            .width(24)
        }
        .justifyContent(FlexAlign.Center)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('sys.color.ohos_id_color_primary'))
        .onClick(() => {
          const command = this.input;
          this.input = '';
          this.runCommand(command);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .padding(16)
  }
}
