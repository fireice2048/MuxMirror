import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

const PREFS_NAME = 'termirror_settings';
const KEY_MUX_GROUPING = 'mux_grouping_mode';

/** 按窗口分组（默认）。 */
export const GROUPING_WINDOW: string = 'window';
/** 按工作目录分组。 */
export const GROUPING_DIRECTORY: string = 'directory';

/**
 * 读取 MUX 导航分组方式。
 * @param context 应用上下文
 * @returns "window" 或 "directory"
 */
export function getMuxGroupingMode(context: Context): string {
  try {
    const pref = preferences.getPreferencesSync(context, { name: PREFS_NAME });
    return pref.getSync(KEY_MUX_GROUPING, GROUPING_WINDOW) as string;
  } catch (err) {
    return GROUPING_WINDOW;
  }
}

/**
 * 写入 MUX 导航分组方式。
 * @param context 应用上下文
 * @param mode "window" 或 "directory"
 */
export function setMuxGroupingMode(context: Context, mode: string): void {
  try {
    const pref = preferences.getPreferencesSync(context, { name: PREFS_NAME });
    pref.putSync(KEY_MUX_GROUPING, mode);
    pref.flushSync();
    AppStorage.setOrCreate('muxGroupingMode', mode);
  } catch (err) {
    // 写入失败时仍更新运行时状态，避免 UI 卡住。
    AppStorage.setOrCreate('muxGroupingMode', mode);
  }
}

/**
 * 初始化：将持久化的分组方式同步到 AppStorage，供全组件订阅。
 * @param context 应用上下文
 */
export function initMuxGroupingMode(context: Context): void {
  const mode = getMuxGroupingMode(context);
  AppStorage.setOrCreate('muxGroupingMode', mode);
}
