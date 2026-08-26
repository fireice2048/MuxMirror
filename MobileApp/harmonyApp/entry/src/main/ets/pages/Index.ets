import {
  deleteConfig, listConfigs, moveConfig, saveConfig, ServerConfig
} from '../core/TermirrorCore';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerListPage } from './ServerListPage';
import { TerminalPage, MuxAttach } from './TerminalPage';
import { NetworkDiagPage } from './NetworkDiagPage';
import { MuxNavPage } from './MuxNavPage';
import { SettingsPage } from './SettingsPage';
import { ServerEditDialog } from '../components/ServerEditDialog';

/** 根页面枚举。 */
type RootPage = 'list' | 'terminal' | 'nav' | 'muxTerminal' | 'diag' | 'settings';

const EMPTY_SERVER: ServerConfig = { name: '', host: '', port: 22, username: '', password: '' };

/**
 * 根页面（壳）：使用 Stack 叠加多页面实例，切换时通过 visibility 控制显隐，
 * 保证导航栈中前面的页面不被销毁，返回出栈时才触发 aboutToDisappear 销毁。
 * 各页面采用懒渲染：第一次 push 时才创建，避免 aboutToAppear 拿到空数据。
 */
@Entry
@Component
struct Index {
  @State page: RootPage = 'list';
  @State servers: ServerConfig[] = [];

  // 各页面独立状态，页面隐藏时仍保留
  @State terminalServer: ServerConfig = EMPTY_SERVER;
  @State navServer: ServerConfig = EMPTY_SERVER;
  /** 每次进入导航页递增，驱动被 Stack 保留的 MuxNavPage 重新查询。 */
  @State navRefreshToken: number = 0;
  @State muxServer: ServerConfig = EMPTY_SERVER;
  @State muxAttach: MuxAttach = { mux: '', session: '' };

  // 懒渲染标记：首次打开后保持 true，组件一直保留在树中
  @State hasOpenedTerminal: boolean = false;
  @State hasOpenedNav: boolean = false;
  @State hasOpenedMuxTerminal: boolean = false;
  @State hasOpenedDiag: boolean = false;
  @State hasOpenedSettings: boolean = false;

  /** 状态栏高度（vp），EntryAbility 注入；用于顶部避让（蓝本 safeDrawingPadding 效果） */
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private editDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.reloadServers();
  }

  private reloadServers(): void {
    const configs = listConfigs();
    hilog.info(0x0000, 'Index', 'reloadServers: count=%{public}d', configs.length);
    this.servers = configs;
  }

  /** 更新列表顺序并持久化；失败时回读已保存顺序。 */
  private reorderServers(from: number, to: number): void {
    if (from < 0 || to < 0 || from >= this.servers.length || to >= this.servers.length || from === to) {
      return;
    }
    const reordered: ServerConfig[] = this.servers.slice();
    const moved: ServerConfig = reordered.splice(from, 1)[0];
    reordered.splice(to, 0, moved);
    this.servers = reordered;
    if (!moveConfig(from, to)) {
      hilog.warn(0x0000, 'Index', 'reorder moveConfig failed, reloading');
      this.reloadServers();
    }
  }

  /** 打开新增/编辑弹窗（server 为 null 表示新增）。 */
  private openEditDialog(server: ServerConfig | null): void {
    this.editDialogController = new CustomDialogController({
      builder: ServerEditDialog({
        server: server,
        onSave: (config: ServerConfig) => {
          hilog.info(0x0000, 'Index', 'onSave: oldName=%{public}s newName=%{public}s host=%{public}s',
            server?.name ?? 'null', config.name, config.host);
          // 编辑场景下若改了名称，需先删除旧名称条目，避免按名称 upsert 造成重复
          if (server !== null && server.name !== config.name) {
            deleteConfig(server.name);
          }
          saveConfig(config);
          this.reloadServers();
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
    });
    this.editDialogController.open();
  }

  /** 删除确认弹窗，对齐蓝本的 AlertDialog。 */
  private confirmDelete(server: ServerConfig): void {
    AlertDialog.show({
      title: '删除服务器',
      message: server.name.length > 0 ? server.name : server.host,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#E84026',
        action: () => {
          deleteConfig(server.name);
          this.reloadServers();
        },
      },
    });
  }

  /** 复制确认弹窗：避免列表页误触复制按钮（人工验收反馈），样式对齐删除确认框。 */
  private confirmCopy(server: ServerConfig): void {
    const source = server.name.length > 0 ? server.name : server.host;
    AlertDialog.show({
      title: '复制服务器',
      message: `将从「${source}」生成一份新的服务器数据`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '复制',
        action: () => {
          this.copyServer(server);
        },
      },
    });
  }

  /** 复制服务器：以“原名 副本”另存一条（名称冲突时追加序号）。 */
  private copyServer(server: ServerConfig): void {
    let copyName = `${server.name} 副本`;
    let seq = 2;
    while (this.servers.some((item: ServerConfig) => item.name === copyName)) {
      copyName = `${server.name} 副本${seq}`;
      seq += 1;
    }
    saveConfig({
      name: copyName,
      host: server.host,
      port: server.port,
      username: server.username,
      password: server.password,
    });
    this.reloadServers();
  }

  /** 从首页打开普通终端页。 */
  private openTerminal(server: ServerConfig): void {
    this.terminalServer = server;
    this.hasOpenedTerminal = true;
    this.page = 'terminal';
  }

  /** 从普通终端页打开导航页。 */
  private openNav(): void {
    this.navServer = this.terminalServer;
    this.hasOpenedNav = true;
    this.navRefreshToken++;
    this.page = 'nav';
  }

  /** 从首页打开设置页。 */
  private openSettings(): void {
    this.hasOpenedSettings = true;
    this.page = 'settings';
  }

  /** 从导航页打开 mux 终端页。 */
  private openMuxTerminal(mux: string, session: string): void {
    this.muxServer = this.navServer;
    this.muxAttach = { mux, session };
    this.hasOpenedMuxTerminal = true;
    this.page = 'muxTerminal';
  }

  /** 返回上一页（pop）。 */
  private goBack(): void {
    if (this.page === 'muxTerminal') {
      this.navRefreshToken++;
      this.page = 'nav';
    } else if (this.page === 'nav') {
      this.page = 'terminal';
    } else if (this.page === 'terminal' || this.page === 'diag' || this.page === 'settings') {
      this.page = 'list';
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 首页服务器列表
      ServerListPage({
        servers: this.servers,
        onOpenLocal: () => {
          this.hasOpenedDiag = true;
          this.page = 'diag';
        },
        onAdd: () => this.openEditDialog(null),
        onOpen: (server: ServerConfig) => this.openTerminal(server),
        onEdit: (server: ServerConfig) => this.openEditDialog(server),
        onCopy: (server: ServerConfig) => this.confirmCopy(server),
        onDelete: (server: ServerConfig) => this.confirmDelete(server),
        onReorder: (from: number, to: number) => this.reorderServers(from, to),
        onOpenSettings: () => this.openSettings(),
      })
        .width('100%')
        .height('100%')
        .visibility(this.page === 'list' ? Visibility.Visible : Visibility.Hidden)

      // 网络诊断页（懒渲染）
      if (this.hasOpenedDiag) {
        NetworkDiagPage({
          onBack: () => this.goBack(),
        })
          .width('100%')
          .height('100%')
          .visibility(this.page === 'diag' ? Visibility.Visible : Visibility.Hidden)
      }

      // 普通终端页：显示 MUX... 按钮，点击打开导航页（懒渲染）
      if (this.hasOpenedTerminal) {
        TerminalPage({
          server: this.terminalServer,
          showNavButton: true,
          onOpenNav: () => this.openNav(),
          onBack: () => this.goBack(),
        })
          .width('100%')
          .height('100%')
          .visibility(this.page === 'terminal' ? Visibility.Visible : Visibility.Hidden)
      }

      // 导航页：全屏 mux 窗口列表（懒渲染）
      if (this.hasOpenedNav) {
        MuxNavPage({
          server: this.navServer,
          refreshToken: this.navRefreshToken,
          onSelect: (mux: string, session: string) => this.openMuxTerminal(mux, session),
          onBack: () => this.goBack(),
        })
          .width('100%')
          .height('100%')
          .visibility(this.page === 'nav' ? Visibility.Visible : Visibility.Hidden)
      }

      // mux 终端页：不显示 MUX... 按钮，连接成功后自动 attach，返回回到导航页（懒渲染）
      if (this.hasOpenedMuxTerminal) {
        TerminalPage({
          server: this.muxServer,
          showNavButton: false,
          attachMux: this.muxAttach,
          onBack: () => this.goBack(),
        })
          .width('100%')
          .height('100%')
          .visibility(this.page === 'muxTerminal' ? Visibility.Visible : Visibility.Hidden)
      }

      // 设置页（懒渲染）
      if (this.hasOpenedSettings) {
        SettingsPage({
          onBack: () => this.goBack(),
        })
          .width('100%')
          .height('100%')
          .visibility(this.page === 'settings' ? Visibility.Visible : Visibility.Hidden)
      }
    }
    .width('100%')
    .height('100%')
    // 沉浸式布局下避让状态栏（蓝本 safeDrawingPadding 效果）
    .padding({ top: this.statusBarHeight })
  }
}
