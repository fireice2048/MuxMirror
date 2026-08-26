/**
 * Rust 核心库 libtermirror_core.so 的 NAPI 类型声明（契约已冻结，Rust 侧按此实现）。
 * 由 MobileApp/shared 中的 termirror_core crate 实现，
 * .so 自身导出 napi_register_module_v1，注册模块名 termirror_core。
 */

/** Rust → UI 方向的事件。诊断事件 sessionId 固定为 0。 */
export interface TmEvent {
  sessionId: number;
  type: 'connectionState' | 'output' | 'error' | 'diag' | 'execResult';
  /** connecting / connected / failed / closed（connectionState）；ok / failed（execResult） */
  state?: string;
  data?: string;
}

/** 注册全局事件回调（Init 后调用一次）。 */
export const tmOnEvent: (cb: (ev: TmEvent) => void) => void;

/** 初始化核心库，传入应用 filesDir（配置/日志落盘位置）。 */
export const tmInit: (filesDir: string) => void;

/**
 * 建立 SSH 会话，返回 sessionId（>0 成功）。
 * paramsJson = {"host":"","port":22,"username":"","password":"","cols":100,"rows":32}
 * 连接状态经 connectionState 事件异步上报。
 */
export const tmSessionConnect: (paramsJson: string) => number;

/** 向会话写入数据（已编码的按键序列或文本）。 */
export const tmSessionWrite: (sessionId: number, data: string) => void;

/** 终端尺寸变化通知。 */
export const tmSessionResize: (sessionId: number, cols: number, rows: number) => void;

/**
 * 执行一次性 SSH exec 命令，同步返回 execId（>0 成功），失败 -1。
 * paramsJson = {"host":"","port":22,"username":"","password":""}
 * 结果经 type='execResult' 事件异步上报：
 *   - 成功：state='ok'，data 为 stdout 文本
 *   - 失败：state='failed'，data 为错误信息
 * 事件 sessionId 字段携带本次返回的 execId，供调用方匹配。
 * 与终端页交互式 PTY 会话相互独立（独立 SSH 会话 + exec channel）。
 */
export const tmSessionExec: (paramsJson: string, command: string) => number;

/** 关闭会话。 */
export const tmSessionClose: (sessionId: number) => void;

/**
 * 按键编码为终端序列。
 * key：可打印字符本身，或 'ESC','TAB','ENTER','BACKSPACE','UP','DOWN','LEFT','RIGHT',
 * 'HOME','END','PGUP','PGDN','DEL','F1'..'F12'。
 */
export const tmEncodeKey: (key: string, ctrl: boolean, alt: boolean) => string;

/** 读取服务器配置列表，返回 JSON 数组 [{"name","host","port","username","password"}]。 */
export const tmConfigList: () => string;

/** 保存（新增或按 name 覆盖）一条服务器配置。 */
export const tmConfigSave: (json: string) => void;

/** 按名称删除服务器配置。 */
export const tmConfigDelete: (name: string) => void;

/** 批量设置配置列表（调试用）。 */
export const tmConfigSeed: (json: string) => void;

/** 按索引移动服务器配置并持久化，返回是否成功。 */
export const tmConfigMove: (from: number, to: number) => boolean;

/** 异步 TCP 连通性检测，结果经 type='diag' 事件返回。 */
export const tmTcpCheck: (host: string, port: number) => void;
