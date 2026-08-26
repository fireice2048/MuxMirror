import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  addEventListener, execSession, removeEventListener, ServerConfig, TmEvent
} from '../core/TermirrorCore';

const DOMAIN = 0x0000;
const TAG = 'TerminalNavPanel';

/** 执行 muxmirror 拉取的终端窗口标签页。 */
export interface NavTab {
  title: string;
  active: boolean;
  /** 所属复用器：TMUX / RMUX */
  mux: string;
  /** 会话名（attach 时作为 rmux/tmux a -t 的目标） */
  session: string;
  /** 工作目录 */
  cwd: string;
}

/** muxmirror 输出的窗口结构。 */
export interface NavWindow {
  app: string;
  pid: number;
  id: number;
  title: string;
  width: number;
  height: number;
  tabs: NavTab[];
}

/** muxmirror 输出的未挂载会话（detached）。 */
export interface NavDetached {
  mux: string;
  session: string;
  cwd: string;
}

/** muxmirror -format json --mux 的完整输出。 */
export interface MuxList {
  windows: NavWindow[];
  detached: NavDetached[];
}

/** 列表项：统一承载「窗口标签页」与「detached 会话」两种来源，便于一行渲染。 */
interface NavItem {
  /** 显示标题：窗口取 window.title；detached 取 session 名 */
  title: string;
  /** 副标题：窗口取活动标签页标题；detached 取 cwd */
  subtitle: string;
  /** 所属复用器（TMUX/RMUX），用于选中后决定 attach 命令前缀 */
  mux: string;
  /** 会话名 */
  session: string;
  /** 多标签页列表（仅窗口来源 >1 时填充，detached 与单标签页为空） */
  tabs: NavTab[];
}

const MUXMIRROR_CMD: string = 'muxmirror -format json --mux';

/**
 * 终端导航浮层：静默 SSH exec 执行 muxmirror，列表展示终端窗口/标签页，
 * 选中后回调 onSelect(mux, session)，由 TerminalPage 往现有 PTY 写 attach 命令。
 *
 * exec 走独立 SSH 会话（与终端页 PTY 互不影响），结果经 execResult 事件上报，
 * 与 connect/tcpCheck 同为后台线程 + 事件驱动模型（不阻塞 UI 线程）。
 */
@Component
export struct TerminalNavPanel {
  @Prop server: ServerConfig;
  onSelect: (mux: string, session: string) => void = () => {
  };
  onCancel: () => void = () => {
  };

  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State items: NavItem[] = [];

  private execId: number = -1;
  private eventListener: (ev: TmEvent) => void = (ev: TmEvent) => {
    if (ev.type !== 'execResult' || ev.sessionId !== this.execId) {
      return;
    }
    if (ev.state === 'ok') {
      this.handleResult(ev.data ?? '');
    } else {
      this.loading = false;
      this.errorMsg = ev.data ?? 'muxmirror 执行失败';
    }
  };

  aboutToAppear(): void {
    addEventListener(this.eventListener);
    this.runExec();
  }

  aboutToDisappear(): void {
    removeEventListener(this.eventListener);
  }

  private runExec(): void {
    this.loading = true;
    this.errorMsg = '';
    this.items = [];
    this.execId = execSession(this.server, MUXMIRROR_CMD);
    if (this.execId <= 0) {
      this.loading = false;
      this.errorMsg = 'exec 通道创建失败';
    }
  }

  /** 解析 muxmirror JSON 输出，按工作目录（cwd）分组聚合。 */
  private handleResult(raw: string): void {
    this.loading = false;
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      this.errorMsg = 'muxmirror 无输出';
      return;
    }
    let list: MuxList;
    try {
      list = JSON.parse(trimmed) as MuxList;
    } catch (err) {
      const preview = trimmed.length > 200 ? trimmed.substring(0, 200) + '...' : trimmed;
      hilog.error(DOMAIN, TAG, 'muxmirror JSON 解析失败: %{public}s, raw=%{public}s', JSON.stringify(err), preview);
      this.errorMsg = `muxmirror 输出解析失败: ${preview}`;
      return;
    }
    const items: NavItem[] = [];
    const groups: Map<string, NavTab[]> = new Map();
    const windows = list.windows ?? [];
    for (const win of windows) {
      const tabs = win.tabs ?? [];
      for (const tab of tabs) {
        const session = tab.session.trim();
        if (session.length === 0) continue;
        const key = tab.cwd.length > 0 ? tab.cwd : session;
        const list = groups.get(key) ?? [];
        list.push(tab);
        groups.set(key, list);
      }
    }
    for (const tabs of groups.values()) {
      const activeTab = tabs.find((t: NavTab) => t.active);
      const representative = activeTab ?? tabs[0];
      items.push({
        title: representative.cwd.length > 0 ? representative.cwd : representative.title,
        subtitle: representative.session,
        mux: representative.mux,
        session: representative.session,
        tabs: tabs,
      });
    }
    const detached = list.detached ?? [];
    for (const d of detached) {
      items.push({
        title: d.session,
        subtitle: d.cwd.length > 0 ? d.cwd : '未挂载',
        mux: d.mux,
        session: d.session,
        tabs: [],
      });
    }
    this.items = items;
    if (items.length === 0) {
      this.errorMsg = '没有终端窗口';
    }
  }

  /** 选中某个标签页：回传 mux + session，并关闭浮层。 */
  private pick(mux: string, session: string): void {
    if (mux.length === 0 || session.length === 0) {
      return;
    }
    this.onSelect(mux, session);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 半透明遮罩：点击空白处取消
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .onClick(() => this.onCancel())

      // 居中卡片
      Column() {
        // 标题栏
        Row() {
          Text('导航')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
          Text('✕')
            .fontSize(18)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => this.onCancel())
        }
        .width('100%')

        if (this.loading) {
          Column({ space: 8 }) {
            LoadingProgress().width(36).height(36)
            Text('正在查询终端窗口...')
              .fontSize(14)
              .fontColor('#66182431')
          }
          .width('100%')
          .height(160)
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMsg.length > 0) {
          Column({ space: 12 }) {
            Text(this.errorMsg)
              .fontSize(14)
              .fontColor('#E84026')
              .textAlign(TextAlign.Center)
              .copyOption(CopyOptions.InApp)
            Button('重试')
              .backgroundColor('#F1F3F5')
              .fontColor('#182431')
              .onClick(() => this.runExec())
          }
          .width('100%')
          .height(160)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 0 }) {
              ForEach(this.items, (item: NavItem, index: number) => {
                Column() {
                  Row() {
                    Column() {
                      Text(item.title)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(item.subtitle)
                        .fontSize(12)
                        .fontColor('#66182431')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    .onClick(() => this.pick(item.mux, item.session))

                    Text(item.mux)
                      .fontSize(11)
                      .fontColor('#198754')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                      .backgroundColor('#E7F4EA')
                      .margin({ left: 4 })

                    if (item.tabs.length > 1) {
                      Text(`${item.tabs.length} 个会话`)
                        .fontSize(11)
                        .fontColor(Color.White)
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(12)
                        .backgroundColor('#198754')
                        .margin({ left: 8 })
                        // 菜单按钮拦截点击不冒泡到行 onClick（pick），避免菜单还没弹出就先选中关闭浮层
                        .hitTestBehavior(HitTestMode.Block)
                        .bindMenu(this.tabMenuElements(item.tabs))
                    }
                  }
                  .width('100%')
                  .padding({ left: 12, right: 8, top: 12, bottom: 12 })
                  .borderRadius(8)
                  .backgroundColor(Color.White)

                  // 列表项之间分隔线（最后一项不画）
                  if (index < this.items.length - 1) {
                    Divider()
                      .color('#F0F1F3')
                      .strokeWidth(0.5)
                      .margin({ left: 12 })
                  }
                }
                .onClick(() => this.pick(item.mux, item.session))
              }, (item: NavItem, index: number) => `${item.mux}:${item.session}:${index}`)
            }
            .width('100%')
          }
          .scrollBar(BarState.Auto)
          .constraintSize({ maxHeight: 360 })
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('80%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
  }

  /** 多标签页窗口的菜单项：每个 tab 一项，点击即选中对应标签页。 */
  private tabMenuElements(tabs: NavTab[]): MenuElement[] {
    return tabs.map((tab: NavTab) => {
      return {
        value: tab.title.length > 0 ? tab.title : tab.session,
        action: () => {
          this.pick(tab.mux, tab.session);
        },
      } as MenuElement;
    });
  }
}
