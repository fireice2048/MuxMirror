import { hilog } from '@kit.PerformanceAnalysisKit';
import termirrorCore from 'libtermirror_core.so';
import {
  EventSignal,
  EventSignalCancellable
} from '../utilities/communication/EventSignal';

const DOMAIN = 0x0000;
const TAG = 'TermirrorCore';

/** Rust → UI 事件，与 libtermirror_core 契约一致。诊断事件 sessionId 固定为 0。 */
export interface TerminalStyleRange {
  start: number;
  end: number;
  /** 文本样式：normal=显式配色，dim=弱化，inverse=前景/背景互换。 */
  style: 'normal' | 'dim' | 'inverse';
  /** ANSI 显式前景色，Rust 核心统一转换为 #RRGGBB。 */
  foreground?: string;
  /** ANSI 显式背景色，Rust 核心统一转换为 #RRGGBB。 */
  background?: string;
}

export interface TmEvent {
  sessionId: number;
  type: string; // 'connectionState' | 'output' | 'error' | 'diag' | 'execResult'
  state?: string; // connecting / connected / failed / closed（connectionState）；ok / failed（execResult）
  data?: string;
  /** 终端光标在 data 中的 UTF-16 码元偏移（仅 output 事件携带）。
   *  主屏模式为快照末尾；备用屏模式为真实光标位置。UI 据此插入本地输入与闪烁光标。 */
  cursor?: number;
  /** 终端快照中的样式区间，起止位置均为 UTF-16 码元偏移。 */
  styles?: TerminalStyleRange[];
  /** 远端请求的鼠标输入协议；仅 output 事件携带。 */
  mouseProtocol?: 'none' | 'x10' | 'sgr';
}

/** 服务器配置，与 tmConfigList/tmConfigSave 的 JSON 结构一致。 */
export interface ServerConfig {
  name: string;
  host: string;
  port: number;
  username: string;
  password: string;
}

export type TmEventListener = (ev: TmEvent) => void;

/** Rust 原生库是否可用（.so 未放入 entry/libs 时为 false，整体降级为 Mock）。 */
export function isNativeReady(): boolean {
  return termirrorCore !== undefined && termirrorCore !== null;
}

// 启动诊断：确认 .so 导入结果（Mock 排查用）
hilog.info(DOMAIN, TAG, 'native 模块导入结果: typeof=%{public}s tmInit=%{public}s tmConfigList=%{public}s',
  typeof termirrorCore,
  isNativeReady() ? typeof termirrorCore.tmInit : 'N/A',
  isNativeReady() ? typeof termirrorCore.tmConfigList : 'N/A');

let initialized = false;

/**
 * Rust → UI 全局事件信号。
 *
 * 页面应保存 on 返回的订阅令牌，并在 aboutToDisappear 时取消。
 */
export const tmEventSignal: EventSignal<TmEvent> = new EventSignal<TmEvent>();

interface LegacyEventSubscription {
  listener: TmEventListener;
  cancellable: EventSignalCancellable;
}

// 未迁移页面的兼容订阅表；新代码直接使用 tmEventSignal。
const legacyEventSubscriptions: LegacyEventSubscription[] = [];

/** 事件总线：Rust 回调统一入口，再通过 EventSignal 派发给页面订阅者。 */
function dispatchEvent(ev: TmEvent): void {
  tmEventSignal.send(ev);
}

/** @deprecated 新代码使用 tmEventSignal.on(callback)。 */
export function addEventListener(cb: TmEventListener): void {
  legacyEventSubscriptions.push({
    listener: cb,
    cancellable: tmEventSignal.on(cb),
  });
}

/** @deprecated 新代码取消 tmEventSignal.on 返回的 EventSignalCancellable。 */
export function removeEventListener(cb: TmEventListener): void {
  const index = legacyEventSubscriptions.findIndex(
    (subscription: LegacyEventSubscription) => subscription.listener === cb
  );
  if (index >= 0) {
    legacyEventSubscriptions[index].cancellable.cancel();
    legacyEventSubscriptions.splice(index, 1);
  }
}

/** 初始化核心库；EntryAbility onCreate 时调用。原生缺失时只打日志，UI 走 Mock。 */
export function initCore(filesDir: string): void {
  if (initialized) {
    return;
  }
  initialized = true;
  if (!isNativeReady()) {
    hilog.warn(DOMAIN, TAG, 'libtermirror_core.so 未加载，UI 以 Mock 模式运行');
    return;
  }
  hilog.info(DOMAIN, TAG, 'tmInit filesDir=%{public}s', filesDir);
  try {
    termirrorCore.tmInit(filesDir);
    termirrorCore.tmOnEvent((ev: TmEvent) => dispatchEvent(ev));
    hilog.info(DOMAIN, TAG, 'Rust 核心库初始化完成');
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Rust 核心库初始化失败: %{public}s', JSON.stringify(err));
  }
}

// ---------------------------------------------------------------------------
// 会话管理
// ---------------------------------------------------------------------------

/** 建立 SSH 会话，返回 sessionId（>0 成功）；连接状态经 connectionState 事件上报。 */
export function connectSession(config: ServerConfig, cols: number, rows: number): number {
  if (!isNativeReady()) {
    return mockConnect(config);
  }
  try {
    const params: string = JSON.stringify({
      host: config.host,
      port: config.port,
      username: config.username,
      password: config.password,
      cols: cols,
      rows: rows,
    });
    return termirrorCore.tmSessionConnect(params);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmSessionConnect 失败: %{public}s', JSON.stringify(err));
    return -1;
  }
}

export function writeSession(sessionId: number, data: string): void {
  if (!isNativeReady()) {
    mockWrite(sessionId, data);
    return;
  }
  try {
    termirrorCore.tmSessionWrite(sessionId, data);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmSessionWrite 失败: %{public}s', JSON.stringify(err));
  }
}

export function resizeSession(sessionId: number, cols: number, rows: number): void {
  if (!isNativeReady()) {
    return; // Mock 不需要尺寸
  }
  try {
    termirrorCore.tmSessionResize(sessionId, cols, rows);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmSessionResize 失败: %{public}s', JSON.stringify(err));
  }
}

/**
 * 执行一次性 SSH exec 命令，同步返回 execId（>0），失败 -1。
 * stdout/错误经 `execResult` 事件异步上报：成功 state='ok'，data 为 stdout；
 * 失败 state='failed'，data 为错误信息。事件 sessionId 字段携带本次返回的 execId，
 * 调用方需订阅 tmEventSignal，并按 (ev.type==='execResult' && ev.sessionId===execId) 过滤。
 * 与终端页交互式 PTY 会话相互独立（独立 SSH 会话 + exec channel）。
 * Mock 模式下返回 -1（导航浮层降级为错误提示）。
 */
export function execSession(config: ServerConfig, command: string): number {
  if (!isNativeReady()) {
    return -1;
  }
  try {
    const params: string = JSON.stringify({
      host: config.host,
      port: config.port,
      username: config.username,
      password: config.password,
    });
    return termirrorCore.tmSessionExec(params, command);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmSessionExec 失败: %{public}s', JSON.stringify(err));
    return -1;
  }
}

export function closeSession(sessionId: number): void {
  if (!isNativeReady()) {
    mockClose(sessionId);
    return;
  }
  try {
    termirrorCore.tmSessionClose(sessionId);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmSessionClose 失败: %{public}s', JSON.stringify(err));
  }
}

/** 按键编码；原生缺失时由本地 Mock 编码（xterm 序列），保证 UI 可浏览。 */
export function encodeKey(key: string, ctrl: boolean, alt: boolean): string {
  if (!isNativeReady()) {
    return mockEncodeKey(key, ctrl, alt);
  }
  try {
    return termirrorCore.tmEncodeKey(key, ctrl, alt);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmEncodeKey 失败: %{public}s', JSON.stringify(err));
    return '';
  }
}

// ---------------------------------------------------------------------------
// 服务器配置存取
// ---------------------------------------------------------------------------

export function listConfigs(): ServerConfig[] {
  if (!isNativeReady()) {
    return mockServers.map((item: ServerConfig) => copyConfig(item));
  }
  try {
    const parsed = JSON.parse(termirrorCore.tmConfigList()) as ServerConfig[];
    hilog.info(DOMAIN, TAG, 'listConfigs: count=%{public}d', parsed.length);
    return parsed;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmConfigList 失败: %{public}s', JSON.stringify(err));
    return [];
  }
}

/** ArkTS 不允许对象字面量展开（arkts-no-spread），显式逐字段拷贝。 */
function copyConfig(config: ServerConfig): ServerConfig {
  return {
    name: config.name,
    host: config.host,
    port: config.port,
    username: config.username,
    password: config.password,
  };
}

/** 批量设置配置列表（调试用）：直接覆盖全部配置并落盘。 */
export function configSeed(json: string): void {
  if (!isNativeReady()) {
    return;
  }
  try {
    termirrorCore.tmConfigSeed(json);
    hilog.info(DOMAIN, TAG, 'configSeed OK');
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmConfigSeed 失败: %{public}s', JSON.stringify(err));
  }
}

/** 新增或按 name 覆盖保存一条配置。 */
export function saveConfig(config: ServerConfig): void {
  if (!isNativeReady()) {
    const index = mockServers.findIndex((item: ServerConfig) => item.name === config.name);
    if (index >= 0) {
      mockServers[index] = copyConfig(config);
    } else {
      mockServers.push(copyConfig(config));
    }
    hilog.info(DOMAIN, TAG, 'saveConfig mock: name=%{public}s host=%{public}s', config.name, config.host);
    return;
  }
  try {
    termirrorCore.tmConfigSave(JSON.stringify(config));
    hilog.info(DOMAIN, TAG, 'saveConfig OK: name=%{public}s host=%{public}s', config.name, config.host);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmConfigSave 失败: %{public}s', JSON.stringify(err));
  }
}

export function deleteConfig(name: string): void {
  if (!isNativeReady()) {
    const index = mockServers.findIndex((item: ServerConfig) => item.name === name);
    if (index >= 0) {
      mockServers.splice(index, 1);
    }
    return;
  }
  try {
    termirrorCore.tmConfigDelete(name);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmConfigDelete 失败: %{public}s', JSON.stringify(err));
  }
}

/** 按索引移动服务器配置并持久化顺序。 */
export function moveConfig(from: number, to: number): boolean {
  if (!isNativeReady()) {
    if (from < 0 || to < 0 || from >= mockServers.length || to >= mockServers.length) {
      return false;
    }
    if (from !== to) {
      const moved: ServerConfig = mockServers.splice(from, 1)[0];
      mockServers.splice(to, 0, moved);
    }
    return true;
  }
  try {
    return termirrorCore.tmConfigMove(from, to);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmConfigMove 失败: %{public}s', JSON.stringify(err));
    return false;
  }
}

// ---------------------------------------------------------------------------
// 网络诊断
// ---------------------------------------------------------------------------

/** 异步 TCP 检测，结果经 type='diag' 事件返回。 */
export function tcpCheck(host: string, port: number): void {
  if (!isNativeReady()) {
    setTimeout(() => {
      dispatchEvent({
        sessionId: 0,
        type: 'diag',
        data: `TCP 连通：${host}:${port}（Mock 结果，原生库未加载）`,
      });
    }, 300);
    return;
  }
  try {
    termirrorCore.tmTcpCheck(host, port);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'tmTcpCheck 失败: %{public}s', JSON.stringify(err));
    dispatchEvent({
      sessionId: 0,
      type: 'diag',
      data: `检测失败：${JSON.stringify(err)}`,
    });
  }
}

// ---------------------------------------------------------------------------
// Mock 实现（.so 缺失时降级，保证全部页面可浏览）
// ---------------------------------------------------------------------------

const mockServers: ServerConfig[] = [
  { name: 'MacBook Pro', host: '10.0.2.2', port: 22, username: 'medie', password: '' },
  { name: 'Linux Workstation', host: '192.168.1.10', port: 2222, username: 'dev', password: '' },
];

let mockSessionSeq = 0;
const mockSnapshots: Map<number, string> = new Map();

function mockConnect(config: ServerConfig): number {
  mockSessionSeq += 1;
  const id = mockSessionSeq;
  mockSnapshots.set(id, '');
  setTimeout(() => {
    dispatchEvent({ sessionId: id, type: 'connectionState', state: 'connected' });
    const snap =
      `Mock 终端：已连接 ${config.username}@${config.host}:${config.port}\n` +
      `（libtermirror_core.so 未加载，以下为本地模拟输出）\n$ `;
    mockSnapshots.set(id, snap);
    dispatchEvent({ sessionId: id, type: 'output', data: snap, cursor: snap.length });
  }, 300);
  return id;
}

function mockWrite(sessionId: number, data: string): void {
  const current = mockSnapshots.get(sessionId);
  if (current === undefined) {
    return;
  }
  // 简单回显：可见字符直接回显，回车追加新提示行，其余控制序列忽略
  let next = current;
  for (const ch of data) {
    if (ch === '\r') {
      next += '\n$ ';
    } else if (ch >= ' ') {
      next += ch;
    }
  }
  mockSnapshots.set(sessionId, next);
  dispatchEvent({ sessionId: sessionId, type: 'output', data: next, cursor: next.length });
}

function mockClose(sessionId: number): void {
  mockSnapshots.delete(sessionId);
}

/** xterm 按键编码的 Mock 版本，与 Rust 侧契约语义保持一致。 */
function mockEncodeKey(key: string, ctrl: boolean, alt: boolean): string {
  const named: Record<string, string> = {
    'ESC': '\u001B', 'TAB': '\t', 'ENTER': '\r', 'BACKSPACE': '\u007F',
    'UP': '\u001B[A', 'DOWN': '\u001B[B', 'RIGHT': '\u001B[C', 'LEFT': '\u001B[D',
    'HOME': '\u001B[H', 'END': '\u001B[F', 'PGUP': '\u001B[5~', 'PGDN': '\u001B[6~', 'DEL': '\u001B[3~',
  };
  let body: string;
  const namedHit = named[key];
  if (namedHit !== undefined) {
    body = namedHit;
  } else if (key.length === 1) {
    body = key;
    if (ctrl) {
      const code = key.toUpperCase().charCodeAt(0);
      if (code >= 64 && code <= 95) {
        body = String.fromCharCode(code - 64);
      }
    }
  } else {
    body = '';
  }
  return alt ? '\u001B' + body : body;
}
