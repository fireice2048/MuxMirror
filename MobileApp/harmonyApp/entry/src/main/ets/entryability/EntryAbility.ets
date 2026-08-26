import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { initCore } from '../core/TermirrorCore';
import { initMuxGroupingMode } from '../core/SettingsStore';

const DOMAIN = 0x0000;
const TAG = 'TermMirror';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '设置 colorMode 失败: %{public}s', JSON.stringify(err));
    }
    // 初始化 Rust 核心库（含事件总线注册）；.so 缺失时内部降级为 Mock
    initCore(this.context.filesDir);
    // 将用户偏好分组方式注入 AppStorage，供导航页和设置页共享。
    initMuxGroupingMode(this.context);
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 主窗口创建完成，加载首页
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, '加载首页失败: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '首页加载成功');
      // 软键盘弹出时压缩窗口（RESIZE），保证终端工具条贴在键盘上方。
      // 必须在 loadContent 完成后调用，否则 UIContent 为空导致 jscrash（API 24 模拟器实测）
      try {
        windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (e) {
        hilog.error(DOMAIN, TAG, '设置 KeyboardAvoidMode 失败: %{public}s', JSON.stringify(e));
      }
    });

    // 全屏沉浸式布局，保留状态栏与导航栏显示
    const win = windowStage.getMainWindowSync();
    win.setWindowLayoutFullScreen(true).then(() => {
      win.setWindowSystemBarEnable(['status', 'navigation']);
      win.setWindowSystemBarProperties({
        // 页面整体为白底，状态栏/导航栏内容色必须用黑色，否则时间电量不可见（人工验收反馈）
        statusBarContentColor: '#000000',
        navigationBarContentColor: '#000000',
      });
      // 把系统避让区高度注入 AppStorage（页面顶部 padding 用）：
      // 沉浸式布局下内容会画到状态栏底下，终端页返回按钮会被状态栏挡住无法点击（人工验收实测）
      try {
        const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        AppStorage.setOrCreate('statusBarHeight', px2vp(avoid.topRect.height));
        // 底部导航栏（指示条）高度：终端工具条据此预留底部边距，避免被屏幕底部横条遮挡。
        // 沉浸式全屏下 TYPE_SYSTEM.bottomRect 可能为 0，需再读 TYPE_NAVIGATION_INDICATOR（手势导航横条）取较大值
        const navIndicator = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        const bottomAvoidPx = Math.max(avoid.bottomRect.height, navIndicator.bottomRect.height);
        AppStorage.setOrCreate('navigationBarHeight', px2vp(bottomAvoidPx));
      } catch (e) {
        hilog.error(DOMAIN, TAG, '获取系统避让区失败: %{public}s', JSON.stringify(e));
      }
    });
  }

  onWindowStageDestroy(): void {
    // 主窗口销毁，释放 UI 相关资源
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
