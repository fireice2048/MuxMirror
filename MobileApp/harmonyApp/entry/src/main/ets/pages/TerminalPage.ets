import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  closeSession, connectSession, resizeSession, ServerConfig, TmEvent, tmEventSignal,
  writeSession
} from '../core/TermirrorCore';
import { TerminalToolbar, ToolbarKey } from '../components/TerminalToolbar';
import { TerminalNativeView } from '../components/TerminalNativeView';
import { TerminalViewController } from '../components/TerminalDisplayContract';
import { EventSignalCancellableSet } from '../utilities/communication/EventSignal';

const DOMAIN = 0x0000;
const TAG = 'TerminalPage';
const CONNECT_TIMEOUT_MS: number = 10000;

/** 连接阶段。 */
type ConnectPhase = 'connecting' | 'connected' | 'failed';

/** mux attach 目标。 */
export interface MuxAttach {
  mux: string;
  session: string;
}

/**
 * 生成从交互式 shell 进入指定 MUX 会话的命令。
 *
 * 手机与桌面共享 pane 时，pane 内的 shell 无法知道一条命令来自哪个 client。
 * 因此禁止执行未指定 client 的 `switch-client`：普通 SSH shell 直接 attach；若
 * 已在任一 MUX 内则拒绝操作，由页面生命周期关闭旧 SSH PTY 后重新连接。
 */
export function buildMuxAttachCommand(mux: string, session: string): string {
  const prefix = mux === 'RMUX' ? 'rmux' : 'tmux';
  const muxEnvironment = '${TMUX-}${RMUX_SESSION-}${RMUX-}';
  const target = shellQuote(session);
  const panClientToBottom =
    `_tm_tty=$(tty); (` +
    `_tm_i=0; while [ "$_tm_i" -lt 20 ]; do ` +
    // attach 完成窗口选择后可能再次重置 viewport，需在注册后的短窗口内持续校正。
    `sleep 0.1; ${prefix} refresh-client -D -t "$_tm_tty" 999 >/dev/null 2>&1 || true; ` +
    `_tm_i=$((_tm_i + 1)); done` +
    `) & `;
  return `if [ -n "${muxEnvironment}" ]; then ` +
    `printf '%s\\n' 'TermMirror: refusing MUX attach from inside an existing MUX session' >&2; ` +
    // 后台任务只通过当前 SSH tty 操作手机客户端，不会切换或移动电脑端 client。
    `else ${panClientToBottom}exec ${prefix} attach-session -f ignore-size -t ${target}; fi`;
}

/** 将 MUX session 名编码为单个 POSIX shell 参数。 */
function shellQuote(value: string): string {
  return `'${value.split("'").join("'\"'\"'")}'`;
}

/**
 * SSH 终端页（编排层）：
 * 连接生命周期（连接中/失败全屏提示）、标题栏、工具条、粘贴叠加层、软键盘状态；
 * 终端画面渲染委托给可切换的显示组件（当前为原生 Text/Span 方案 TerminalNativeView，
 * 后续可挂载 xterm.js 方案 TerminalWebView 做 A/B 对比）。
 */
@Component
export struct TerminalPage {
  @Prop @Watch('onServerOrMuxChanged') server: ServerConfig = { name: '', host: '', port: 22, username: '', password: '' };
  onBack: () => void = () => {
  };
  /** 是否显示标题栏「MUX...」导航按钮。从导航页进入的 mux 终端应隐藏。 */
  showNavButton: boolean = true;
  /** 若指定，连接成功后自动 attach 到对应 mux session。 */
  @Prop @Watch('onServerOrMuxChanged') attachMux: MuxAttach = { mux: '', session: '' };
  /** 点击「MUX...」按钮时由调用方打开导航页。 */
  onOpenNav?: () => void = () => {
  };

  @State phase: ConnectPhase = 'connecting';
  @State errorText: string = '';
  @State controlLocked: boolean = false;
  @State altLocked: boolean = false;
  @State keyboardVisible: boolean = false;
  @State keyboardRequestedVisible: boolean = false;
  /** 屏幕底部导航栏（指示条）高度 vp，由 EntryAbility 注入 AppStorage。
   *  工具条据此预留底部边距，避免被屏幕底部横条遮挡；软键盘升起后边距收为 0。 */
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  @State sessionId: number = -1;
  private viewController: TerminalViewController = new TerminalViewController();
  private mainWindow: window.Window | null = null;
  private connectTimer: number = -1;
  private keyboardRequestTimer: number = -1;
  private eventCancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
  /** MUX 键盘弹出前的完整 PTY 行数；键盘显示期间保留该高度供本地 Scroll 浏览。 */
  private expandedMuxRows: number = 0;

  private eventListener: (ev: TmEvent) => void = (ev: TmEvent) => {
    if (ev.sessionId !== this.sessionId) {
      return;
    }
    if (ev.type === 'connectionState') {
      if (ev.state === 'connected') {
        this.phase = 'connected';
        this.clearConnectTimer();
        // PTY 尺寸同步由显示组件 @Watch('connected') 重发已测行列数触发
        // 若从导航页指定了 mux session，连接成功后自动 attach
        if (this.attachMux.mux.length > 0 && this.attachMux.session.length > 0) {
          this.attachToMux(this.attachMux.mux, this.attachMux.session);
        }
      } else if (ev.state === 'failed') {
        this.phase = 'failed';
        this.errorText = ev.data ?? 'SSH 连接失败';
        this.clearConnectTimer();
      } else if (ev.state === 'closed') {
        this.phase = 'failed';
        this.errorText = '会话已关闭';
        this.clearConnectTimer();
      }
    } else if (ev.type === 'error') {
      this.phase = 'failed';
      this.errorText = ev.data ?? '未知错误';
    }
  };

  private keyboardCallback: (height: number) => void = (height: number) => {
    this.keyboardVisible = height > 0;
    hilog.info(DOMAIN, TAG, '键盘高度变化: %{public}d visible=%{public}s',
      height, this.keyboardVisible.toString());
    // 系统高度回调是键盘真实状态，收到后即可结束“正在请求”状态。
    this.keyboardRequestedVisible = false;
    this.clearKeyboardRequestTimer();
  };

  aboutToAppear(): void {
    this.eventCancellables.cancelAll();
    tmEventSignal.on(this.eventListener).into(this.eventCancellables);
    // 监听软键盘高度，决定 ⏏ 翻转与工具条避让
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.mainWindow = win;
      win.on('keyboardHeightChange', this.keyboardCallback);
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, '获取主窗口失败: %{public}s', err.message);
    });
    // 首次创建时直接连接；后续 server/attachMux 变化由 @Watch 处理
    if (this.server.host.length > 0) {
      this.startConnect();
    }
  }

  /** server 或 attachMux 变化时：关闭旧会话并重新连接（用于 Stack 叠加保持实例的场景）。 */
  private onServerOrMuxChanged(): void {
    if (this.server.host.length === 0) {
      return;
    }
    if (this.sessionId > 0) {
      closeSession(this.sessionId);
      this.sessionId = -1;
    }
    this.clearConnectTimer();
    this.startConnect();
  }

  aboutToDisappear(): void {
    this.eventCancellables.cancelAll();
    this.clearConnectTimer();
    this.clearKeyboardRequestTimer();
    if (this.mainWindow !== null) {
      this.mainWindow.off('keyboardHeightChange', this.keyboardCallback);
    }
    if (this.sessionId > 0) {
      closeSession(this.sessionId);
      this.sessionId = -1;
    }
  }

  private startConnect(): void {
    this.phase = 'connecting';
    this.expandedMuxRows = 0;
    this.sessionId = connectSession(this.server, 100, 32);
    if (this.sessionId <= 0) {
      this.phase = 'failed';
      this.errorText = '会话创建失败';
      return;
    }
    // 10 秒连接超时，对齐蓝本 SERVER_CONNECTION_TIMEOUT_MS
    this.connectTimer = setTimeout(() => {
      if (this.phase === 'connecting') {
        this.phase = 'failed';
        this.errorText = '连接超时';
        closeSession(this.sessionId);
      }
    }, CONNECT_TIMEOUT_MS);
  }

  private clearConnectTimer(): void {
    if (this.connectTimer !== -1) {
      clearTimeout(this.connectTimer);
      this.connectTimer = -1;
    }
  }

  // ------------------------------------------------------------------
  // mux attach
  // ------------------------------------------------------------------

  /** 新建 SSH PTY 连接成功后，向普通登录 shell 写入一次 attach 命令。
   *  手机 client 使用 ignore-size：自身 PTY 仍可 resize，但不参与共享 MUX window
   *  的尺寸计算，避免电脑端窗口与历史内容被手机尺寸重排。
   *  当共享 window 比手机 PTY 高时，MUX 默认展示顶部裁剪区域；attach 后按 tty
   *  找到刚注册的手机客户端并将其可见区域平移到底部，保证 TUI 输入行和页脚可见。 */
  private attachToMux(mux: string, session: string): void {
    if (this.sessionId <= 0 || session.length === 0) {
      return;
    }
    writeSession(this.sessionId, `${buildMuxAttachCommand(mux, session)}\r`);
  }

  // ------------------------------------------------------------------
  // 显示组件回调
  // ------------------------------------------------------------------

  /** 显示组件的用户输入 → 写入会话。 */
  private handleInput(data: string): void {
    if (this.sessionId > 0) {
      writeSession(this.sessionId, data);
    }
  }

  /** 显示组件的尺寸变化 → 已连接时同步 PTY。 */
  private handleResize(cols: number, rows: number): void {
    if (this.phase === 'connected' && this.sessionId > 0) {
      let targetRows = rows;
      if (this.attachMux.mux.length > 0) {
        // ArkUI 布局缩小可能早于 keyboardHeightChange 回调。工具条已发起键盘请求时
        // 也必须按键盘活动态处理，否则会先把完整行数覆盖成缩小后的行数，
        // 随后的 Math.max 无法恢复，MUX 输入行和页脚会被裁出手机收到的快照。
        const keyboardActive = this.keyboardVisible || this.keyboardRequestedVisible;
        if (!keyboardActive) {
          this.expandedMuxRows = rows;
        } else if (this.expandedMuxRows > 0) {
          // ignore-size 只保护共享 window；若仍把手机 PTY 缩到键盘上方高度，
          // tmux 会只发送裁剪后的局部画面，本地 Scroll 也无法找回输入区。
          targetRows = Math.max(rows, this.expandedMuxRows);
        }
      }
      resizeSession(this.sessionId, cols, targetRows);
    }
  }

  // ------------------------------------------------------------------
  // 工具条与键盘
  // ------------------------------------------------------------------

  /** 工具条按键分发：CTRL/ALT/KBD/PAST 为页面级共享逻辑，其余转发给显示组件。 */
  private onToolKey(key: ToolbarKey): void {
    switch (key) {
      case 'CTRL':
        this.controlLocked = !this.controlLocked;
        break;
      case 'ALT':
        this.altLocked = !this.altLocked;
        break;
      case 'KBD':
        this.toggleKeyboard();
        break;
      case 'PAST':
        this.pasteClipboardText();
        break;
      default:
        this.viewController.handleToolKey(key);
        break;
    }
  }

  /** 读取剪贴板，经显示组件控制器粘贴（native 插入本地缓冲；xterm 送入终端）。 */
  private pasteClipboardText(): void {
    pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
      const text = data.getPrimaryText();
      if (text !== undefined && text.length > 0) {
        this.viewController.paste(text);
      }
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, '读取剪贴板失败: %{public}s', err.message);
    });
  }

  /** ⏏：切换软键盘显示/隐藏。 */
  private toggleKeyboard(): void {
    const active = this.keyboardVisible || this.keyboardRequestedVisible;
    hilog.info(DOMAIN, TAG, '切换键盘: visible=%{public}s requested=%{public}s active=%{public}s',
      this.keyboardVisible.toString(), this.keyboardRequestedVisible.toString(), active.toString());
    if (!active) {
      this.keyboardRequestedVisible = true;
      this.viewController.focus();
      this.clearKeyboardRequestTimer();
      // IME client 已脱离时 showTextInput 会失败且没有高度回调；超时释放请求态，
      // 让用户下一次点击能够重新聚焦并重试，而不是永远走“收起”分支。
      this.keyboardRequestTimer = setTimeout(() => {
        if (!this.keyboardVisible) {
          this.keyboardRequestedVisible = false;
        }
        this.keyboardRequestTimer = -1;
      }, 800);
    } else {
      this.keyboardRequestedVisible = false;
      this.clearKeyboardRequestTimer();
      void this.viewController.blur();
    }
  }

  /** 页面切换前先解除隐藏输入框焦点并等待输入法收起，避免键盘状态泄漏到下一页。 */
  private leaveTerminal(action: () => void): void {
    this.keyboardRequestedVisible = false;
    this.clearKeyboardRequestTimer();
    void this.viewController.blur().then(() => action());
  }

  private clearKeyboardRequestTimer(): void {
    if (this.keyboardRequestTimer !== -1) {
      clearTimeout(this.keyboardRequestTimer);
      this.keyboardRequestTimer = -1;
    }
  }

  /** 工具条底部边距：无软键盘时预留屏幕底部导航指示条高度，避免按键被遮挡；
   *  软键盘升起后收为 0，保证工具条紧贴键盘不过远。 */
  private toolbarBottomPadding(): number {
    // 导航避让边距按指示条高度的 60% 预留（人工验收：全高太抬升工具条，减 40%）
    return 2.4 + (this.keyboardVisible ? 0 : this.navigationBarHeight * 0.6);
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.phase !== 'connected') {
        // 连接中 / 失败 全屏提示，对齐蓝本的 connecting/connectionError 分支
        Column({ space: 12 }) {
          if (this.phase === 'connecting') {
            LoadingProgress()
              .width(48)
              .height(48)
          }
          Text(this.phase === 'connecting' ?
            `Loading · 正在连接 ${this.server.host}:${this.server.port}` : this.errorText)
            .fontSize(14)
            .textAlign(TextAlign.Center)
            .copyOption(CopyOptions.InApp)
          Button(this.attachMux.mux.length > 0 ? '返回导航' : '返回服务器列表')
            .backgroundColor(Color.Transparent)
            .fontColor($r('sys.color.ohos_id_color_primary'))
            .onClick(() => this.leaveTerminal(() => this.onBack()))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else {
        Column() {
          Column() {
            // 标题栏：服务器名 + ssh 摘要 + 返回
            Row() {
              Column() {
                Text(this.server.name.length > 0 ? this.server.name : this.server.host)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                Text(`ssh ${this.server.username}@${this.server.host}:${this.server.port}`)
                  .fontSize(12)
                  .fontColor('#66182431')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.showNavButton) {
                Button('MUX...')
                  .backgroundColor(Color.Transparent)
                  .fontColor($r('sys.color.ohos_id_color_primary'))
                  .enabled(this.phase === 'connected')
                  .onClick(() => {
                    if (this.onOpenNav !== undefined) {
                      this.leaveTerminal(() => this.onOpenNav?.());
                    }
                  })
              }
              Button('返回')
                .backgroundColor(Color.Transparent)
                .fontColor($r('sys.color.ohos_id_color_primary'))
                .onClick(() => this.leaveTerminal(() => this.onBack()))
            }
            .width('100%')

            // 终端显示组件（当前为原生 Text/Span 方案；xterm.js 方案接入后按 backend 切换）
            TerminalNativeView({
              sessionId: this.sessionId,
              connected: this.phase === 'connected',
              controlLocked: this.controlLocked,
              altLocked: this.altLocked,
              controller: this.viewController,
              onInput: (data: string) => this.handleInput(data),
              onResize: (cols: number, rows: number) => this.handleResize(cols, rows),
            })
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 4.8, right: 4.8, top: 2.4, bottom: 2.4 })

          // 两行 20 键工具条（RESIZE 避让模式下自动位于软键盘上方）
          // 底部边距：无键盘时避开屏幕底部导航指示条；键盘升起后收为 0，紧贴键盘
          TerminalToolbar({
            controlLocked: this.controlLocked,
            altLocked: this.altLocked,
            onKeyAction: (key: ToolbarKey) => this.onToolKey(key),
          })
            .width('100%')
            .padding({ left: 4.8, right: 4.8, top: 2.4, bottom: this.toolbarBottomPadding() })
            .animation({ duration: 200, curve: Curve.EaseOut })
        }
        .width('100%')
        .height('100%')

        // 安全粘贴叠加层（蓝本 ArkUI PasteButton 模式：终端激活时显示）
        Row() {
          Blank().width('20%')
          PasteButton({ text: PasteDescription.PASTE, buttonType: ButtonType.Normal })
            .width('10%')
            .height(32)
            .fontSize(12)
            .fontColor('#198754')
            .backgroundColor('#E7F4EA')
            .borderRadius(4)
            .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
              if (result === PasteButtonOnClickResult.SUCCESS) {
                this.pasteClipboardText();
              }
            })
        }
        .width('100%')
        // 底部边距与工具条同步（toolbarBottomPadding）：工具条因导航避让上移时，
        // 粘贴按钮须跟着上移以覆盖 PAST 键位置，否则会掉到屏幕底部导航区
        .padding({ left: 4.8, right: 4.8, bottom: this.toolbarBottomPadding() })
        .hitTestBehavior(HitTestMode.Transparent)
      }

    }
    .width('100%')
    .height('100%')
  }
}
