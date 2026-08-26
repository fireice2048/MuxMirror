import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  addEventListener, execSession, removeEventListener, ServerConfig, TmEvent
} from '../core/TermirrorCore';
import { NavTab, NavWindow, NavDetached, MuxList } from '../components/TerminalNavPanel';

const DOMAIN = 0x0000;
const TAG = 'MuxNavPage';

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

/** 按 mux + session 去重，避免同一会话的多个 attached client 重复出现在导航。 */
export function uniqueMuxTabs(tabs: NavTab[]): NavTab[] {
  const seen: Set<string> = new Set();
  return tabs.filter((tab: NavTab) => {
    const key = `${tab.mux.toUpperCase()}:${tab.session.trim()}`;
    if (tab.session.trim().length === 0 || tab.mux.length === 0 || seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

/**
 * MUX 导航页面：全屏展示远端终端窗口/标签页列表。
 * 选中标签页后回调 onSelect(mux, session)，由调用方打开 mux 终端页。
 */
@Component
export struct MuxNavPage {
  @Prop @Watch('onServerChanged') server: ServerConfig = { name: '', host: '', port: 22, username: '', password: '' };
  /** 每次页面重新进入时由 Index 递增，避免 Visibility.Hidden 保留旧导航结果。 */
  @Prop @Watch('onRefreshRequested') refreshToken: number = 0;
  onSelect: (mux: string, session: string) => void = () => {
  };
  onBack: () => void = () => {
  };

  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State items: NavItem[] = [];
  @StorageProp('muxGroupingMode') groupingMode: string = 'window';
  @State useServerDirectory: boolean = false;
  /** 长按走马灯时显示气泡的列表项索引，-1 表示不显示。 */
  @State bubbleIndex: number = -1;
  /** 气泡要显示的完整文字。 */
  @State bubbleText: string = '';
  /** 自动重试次数。 */
  @State retryCount: number = 0;
  /** 当前重试提示文案。 */
  @State retryMsg: string = '';

  private readonly MAX_RETRY: number = 3;
  private execId: number = -1;
  private retryTimer: number = -1;
  private eventListener: (ev: TmEvent) => void = (ev: TmEvent) => {
    if (ev.type !== 'execResult' || ev.sessionId !== this.execId) {
      return;
    }
    if (ev.state === 'ok') {
      this.handleResult(ev.data ?? '');
    } else if (this.groupingMode === 'directory' && this.useServerDirectory) {
      // 服务端可能还不支持 --by-directory，退回到客户端分组。
      this.useServerDirectory = false;
      this.retryCount = 0;
      this.retryMsg = '';
      this.runExec();
    } else {
      this.scheduleRetry(ev.data ?? 'muxmirror 执行失败');
    }
  };

  aboutToAppear(): void {
    addEventListener(this.eventListener);
    this.useServerDirectory = this.groupingMode === 'directory';
    // 首次创建时直接查询；后续 server 变化由 @Watch 重新查询
    if (this.server.host.length > 0) {
      this.runExec();
    }
  }

  /** server 变化时重新查询 muxmirror（用于 Stack 叠加保持实例的场景）。 */
  private onServerChanged(): void {
    this.useServerDirectory = this.groupingMode === 'directory';
    if (this.server.host.length > 0) {
      this.runExec();
    }
  }

  /** 页面实例被 Stack 保留时，显式刷新窗口、分组设置和 session 状态。 */
  private onRefreshRequested(): void {
    this.useServerDirectory = this.groupingMode === 'directory';
    if (this.server.host.length > 0) {
      this.runExec();
    }
  }

  aboutToDisappear(): void {
    removeEventListener(this.eventListener);
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private runExec(isRetry: boolean = false): void {
    if (!isRetry) {
      this.retryCount = 0;
      this.retryMsg = '';
    }
    this.loading = true;
    this.errorMsg = '';
    this.items = [];
    const flag = (this.groupingMode === 'directory' && this.useServerDirectory) ? ' --by-directory' : '';
    this.execId = execSession(this.server, `muxmirror -format json --mux${flag}`);
    if (this.execId <= 0) {
      this.scheduleRetry('exec 通道创建失败');
    }
  }

  /** 自动重试调度：最多 MAX_RETRY 次，期间显示重试提示。 */
  private scheduleRetry(reason: string): void {
    if (this.retryCount < this.MAX_RETRY) {
      this.retryCount++;
      this.retryMsg = `正在重试第 ${this.retryCount} 次...`;
      this.loading = true;
      this.errorMsg = '';
      this.retryTimer = setTimeout(() => {
        this.retryTimer = -1;
        this.runExec(true);
      }, 1000);
    } else {
      this.loading = false;
      this.errorMsg = reason;
      this.retryMsg = '';
      this.retryCount = 0;
    }
  }

  /** 解析 muxmirror JSON 输出。 */
  private handleResult(raw: string): void {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      if (this.groupingMode === 'directory' && this.useServerDirectory) {
        this.useServerDirectory = false;
        this.retryCount = 0;
        this.retryMsg = '';
        this.runExec();
      } else {
        this.loading = false;
        this.errorMsg = 'muxmirror 无输出';
      }
      return;
    }
    let list: MuxList;
    try {
      list = JSON.parse(trimmed) as MuxList;
    } catch (err) {
      if (this.groupingMode === 'directory' && this.useServerDirectory) {
        this.useServerDirectory = false;
        this.retryCount = 0;
        this.retryMsg = '';
        this.runExec();
      } else {
        const preview = trimmed.length > 200 ? trimmed.substring(0, 200) + '...' : trimmed;
        hilog.error(DOMAIN, TAG, 'muxmirror JSON 解析失败: %{public}s, raw=%{public}s', JSON.stringify(err), preview);
        this.loading = false;
        this.errorMsg = `muxmirror 输出解析失败: ${preview}`;
      }
      return;
    }
    const items: NavItem[] = [];
    const windows = list.windows ?? [];

    if (this.groupingMode === 'window') {
      for (const win of windows) {
        const tabs = uniqueMuxTabs(win.tabs ?? []);
        if (tabs.length === 0) continue;
        const activeTab = tabs.find((t: NavTab) => t.active);
        const representative = activeTab ?? tabs[0];
        items.push({
          title: win.title.length > 0 ? win.title : representative.session,
          subtitle: representative.session,
          mux: representative.mux,
          session: representative.session,
          tabs: tabs,
        });
      }
    } else {
      // 按工作目录（cwd）分组聚合所有 tmux/rmux 标签页
      const groups: Map<string, NavTab[]> = new Map();
      const groupTitles: Map<string, string> = new Map();
      const seenSessions: Set<string> = new Set();
      for (const win of windows) {
        const tabs = win.tabs ?? [];
        for (const tab of tabs) {
          const session = tab.session.trim();
          if (session.length === 0) continue;
          const identity = `${tab.mux.toUpperCase()}:${session}`;
          if (seenSessions.has(identity)) continue;
          seenSessions.add(identity);
          // 新版 muxmirror 的 --by-directory 会把目录放在 window.title；旧版仍可
          // 通过 tab.cwd 分组。两者都为空时才以 session 保底。
          const directory = tab.cwd.length > 0 ? tab.cwd : win.title;
          const key = directory.length > 0 ? directory : session;
          const list = groups.get(key) ?? [];
          list.push(tab);
          groups.set(key, list);
          groupTitles.set(key, directory.length > 0 ? directory : session);
        }
      }
      groups.forEach((tabs: NavTab[], key: string) => {
        const activeTab = tabs.find((t: NavTab) => t.active);
        const representative = activeTab ?? tabs[0];
        items.push({
          title: groupTitles.get(key) ?? key,
          subtitle: representative.session,
          mux: representative.mux,
          session: representative.session,
          tabs: tabs,
        });
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
      if (this.groupingMode === 'directory' && this.useServerDirectory) {
        this.useServerDirectory = false;
        this.retryCount = 0;
        this.retryMsg = '';
        this.runExec();
      } else {
        this.loading = false;
        this.scheduleRetry('没有终端窗口');
      }
    } else {
      this.loading = false;
      this.retryCount = 0;
      this.retryMsg = '';
    }
  }

  /** 选中某个标签页：回传 mux + session，由调用方打开 mux 终端。 */
  private pick(mux: string, session: string): void {
    if (mux.length === 0 || session.length === 0) {
      return;
    }
    this.onSelect(mux, session);
  }

  /** 多标签页弹出菜单：宽度撑满屏幕，支持多行显示，最大高度 500。
   *  每个会话显示 MUX 标签徽章（样式对齐列表行），会话之间画分割线。 */
  @Builder
  TabMenuBuilder(tabs: NavTab[]) {
    Menu() {
      ForEach(tabs, (tab: NavTab, index: number) => {
        MenuItemGroup() {
          MenuItem() {
            Column() {
              Row() {
                Text(`${tab.mux}[${tab.session}]`)
                  .fontSize(11)
                  .fontColor('#198754')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor('#E7F4EA')
                  .margin({ right: 6 })
                Text(tab.title.length > 0 ? tab.title : tab.session)
                  .fontSize(14)
                  .fontColor('#182431')
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 12, right: 12, top: 12, bottom: 12 })

              // 会话之间分割线（最后一项不画）
              if (index < tabs.length - 1) {
                Divider()
                  .color('#F0F1F3')
                  .strokeWidth(0.5)
                  .margin({ left: 12 })
              }
            }
            .width('100%')
            .constraintSize({ minHeight: 44, maxHeight: 500 })
            .clip(true)
          }
          .onClick(() => this.pick(tab.mux, tab.session))
        }
      }, (tab: NavTab, index: number) => `${tab.mux}:${tab.session}:${index}`)
    }
    .width('100%')
  }

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
        Text('导航')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank()
          .width(36)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })

      if (this.loading) {
        Column({ space: 8 }) {
          LoadingProgress().width(36).height(36)
          Text(this.retryMsg.length > 0 ? this.retryMsg : '正在查询终端窗口...')
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
                  Column({ space: 8 }) {
                    Row() {
                      Text(item.title)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#182431')
                        .layoutWeight(1)

                      if (item.tabs.length > 1) {
                        Column() {
                          Text(`${item.tabs.length} 个会话`)
                            .fontSize(12)
                            .fontColor(Color.White)
                            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                            .borderRadius(14)
                            .backgroundColor('#198754')
                        }
                        .alignSelf(ItemAlign.Stretch)
                        .justifyContent(FlexAlign.Center)
                        .margin({ left: 8 })
                        .hitTestBehavior(HitTestMode.Block)
                        .bindMenu(this.TabMenuBuilder(item.tabs))
                      }
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)

                    Row() {
                      Text(`${item.mux}[${item.session}]`)
                        .fontSize(11)
                        .fontColor('#198754')
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(4)
                        .backgroundColor('#E7F4EA')
                        .margin({ right: 6 })
                      Text(item.subtitle)
                        .fontSize(12)
                        .fontColor('#66182431')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.MARQUEE })
                        .marqueeOptions({ start: true, step: 2, loop: -1, delay: 1000 })
                        .layoutWeight(1)
                        .bindPopup(this.bubbleIndex === index, {
                          message: this.bubbleText,
                          placementOnTop: true,
                          primaryButton: {
                            value: '',
                            action: () => {
                            }
                          }
                        })
                        .gesture(
                          LongPressGesture({ duration: 500 })
                            .onAction(() => {
                              this.bubbleText = item.subtitle;
                              this.bubbleIndex = index;
                            })
                            .onActionEnd(() => {
                              this.bubbleIndex = -1;
                            })
                        )
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .onClick(() => this.pick(item.mux, item.session))
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .constraintSize({ minHeight: 72 })
                .padding({ left: 12, right: 8, top: 12, bottom: 12 })
                .borderRadius(8)
                .backgroundColor(Color.White)

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
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Auto)
        .constraintSize({ maxHeight: '100%' })
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
    .padding({ left: 6, right: 6, bottom: 12 })
  }
}
