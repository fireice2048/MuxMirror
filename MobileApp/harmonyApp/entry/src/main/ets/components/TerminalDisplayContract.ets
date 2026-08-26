/**
 * 终端显示组件契约：定义显示后端的类型与命令式桥。
 *
 * 两个显示组件（TerminalNativeView / TerminalWebView）遵循相同的 props/回调签名
 * （ArkTS @Component 不支持运行时动态多态，TerminalPage 用 if/else 选择挂载）：
 *   @Prop sessionId: number          事件总线过滤 + 会话归属
 *   @Prop connected: boolean         连接态（翻转时重发尺寸）
 *   @Prop controlLocked: boolean     CTRL 锁定（工具条维护，显示侧只读）
 *   @Prop altLocked: boolean         ALT 锁定
 *   controller: TerminalViewController  命令式桥（aboutToAppear 注入实现）
 *   onInput: (data: string) => void     用户输入 → 父级 writeSession
 *   onResize: (cols, rows) => void      尺寸 → 父级 resizeSession
 */
import { ToolbarKey } from './TerminalToolbar';

/** 终端显示后端类型。 */
export type TerminalBackend = 'native' | 'xterm';
export type TerminalMouseProtocol = 'none' | 'x10' | 'sgr';
export type TerminalWheelDirection = 'up' | 'down';

export interface TerminalWheelBatch {
  direction: TerminalWheelDirection;
  steps: number;
  remainder: number;
}

/** 将连续手势位移量化为有限个滚轮刻度。正位移（手指向下拖）对应向上回看。 */
export function consumeTerminalWheelDelta(
  remainder: number,
  deltaY: number,
  threshold: number = 28,
  maxSteps: number = 4
): TerminalWheelBatch {
  const safeThreshold = Math.max(1, threshold);
  const total = remainder + deltaY;
  const direction: TerminalWheelDirection = total >= 0 ? 'up' : 'down';
  const rawSteps = Math.floor(Math.abs(total) / safeThreshold);
  return {
    direction,
    steps: Math.min(Math.max(0, maxSteps), rawSteps),
    // 大幅快速滑动的超额刻度直接丢弃，只保留不足一个刻度的尾数，避免输入洪峰。
    remainder: total % safeThreshold,
  };
}

/** 编码 xterm 鼠标滚轮事件。坐标为 1 起；X10 因字符串 UTF-8 通道限制钳到 ASCII 范围。 */
export function encodeTerminalWheel(
  protocol: TerminalMouseProtocol,
  direction: TerminalWheelDirection,
  column: number,
  row: number,
  repeat: number = 1
): string {
  if (protocol === 'none') {
    return '';
  }
  const button = direction === 'up' ? 64 : 65;
  const count = Math.min(16, Math.max(0, Math.floor(repeat)));
  let encoded = '';
  if (protocol === 'sgr') {
    const col = clampTerminalCoordinate(column, 9999);
    const line = clampTerminalCoordinate(row, 9999);
    const event = `\x1B[<${button};${col};${line}M`;
    for (let i = 0; i < count; i++) {
      encoded += event;
    }
    return encoded;
  }

  const col = clampTerminalCoordinate(column, 95);
  const line = clampTerminalCoordinate(row, 95);
  const event = `\x1B[M${String.fromCharCode(32 + button)}${String.fromCharCode(32 + col)}` +
    `${String.fromCharCode(32 + line)}`;
  for (let i = 0; i < count; i++) {
    encoded += event;
  }
  return encoded;
}

function clampTerminalCoordinate(value: number, maximum: number): number {
  return Math.min(maximum, Math.max(1, Math.floor(value)));
}

/**
 * TerminalPage → 显示组件的命令式桥（对齐 ArkUI Scroller/TextInputController 模式）。
 * 显示组件在 aboutToAppear 时注入各回调实现；TerminalPage 在工具条/粘贴/键盘事件时调用。
 */
export class TerminalViewController {
  /** 工具条按键的后端相关部分（CTRL/ALT/KBD/PAST 由 TerminalPage 自行处理，其余转发）。 */
  handleToolKey: (key: ToolbarKey) => void = () => {};
  /** 粘贴文本（native：插入本地缓冲；xterm：送入终端）。 */
  paste: (text: string) => void = () => {};
  /** 聚焦并唤起软键盘。 */
  focus: () => void = () => {};
  /** 清除输入焦点并收起软键盘；页面切换可等待完成后再继续。 */
  blur: () => Promise<void> = async () => {};
}

/** 为 Stack 中并存的多个终端生成唯一输入焦点 ID。 */
export function terminalInputFocusId(sessionId: number): string {
  return `tmHiddenInput-${sessionId}`;
}

/** 覆盖式光标渲染后应跳过的原字符长度。
 *  普通字符由光标块替代；换行符必须保留，否则下一行会拼到光标所在行。 */
export function terminalCursorCharSkip(cursorChar: string): number {
  return cursorChar === '\n' ? 0 : cursorChar.length;
}

/** 请求隐藏输入框聚焦；键盘是否弹起由组件自己的 onFocus 状态控制。 */
export async function requestKeyboardFocus(
  requestFocus: (id: string) => void,
  schedule: (task: () => void) => void = (task: () => void) => setTimeout(task, 0),
  inputId: string = 'tmHiddenInput'
): Promise<void> {
  requestFocus(inputId);
  await new Promise<void>((resolve: () => void) => {
    schedule(() => resolve());
  });
}
