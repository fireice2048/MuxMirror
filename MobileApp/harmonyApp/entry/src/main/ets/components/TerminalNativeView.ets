/**
 * 原生终端显示组件（Text/Span 方案）：
 * 可滚动输出快照（Rust TerminalBuffer 解析后的整屏文本）+ 行内输入。
 * 本地输入缓冲与闪烁光标直接渲染在快照末尾（真实提示词之后），
 * 不单独绘制输入区——光标就闪烁在真实输入位置，与真实终端一致。
 *
 * 数据流：订阅事件总线的 output 事件（整屏快照整体替换）；
 * 用户输入经 onInput 回调交父级写入会话；尺寸变化经 onResize 回调交父级同步 PTY。
 * 隐藏 1dp TextInput 仅用于唤起软键盘接收文本。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { inputMethod } from '@kit.IMEKit';
import {
  addEventListener, encodeKey, removeEventListener, TerminalStyleRange, TmEvent
} from '../core/TermirrorCore';
import { ToolbarKey } from './TerminalToolbar';
import {
  consumeTerminalWheelDelta, encodeTerminalWheel, requestKeyboardFocus, terminalCursorCharSkip,
  terminalInputFocusId, TerminalMouseProtocol, TerminalViewController, TerminalWheelDirection
} from './TerminalDisplayContract';

const DOMAIN = 0x0000;
const TAG = 'TerminalNativeView';
const TERMINAL_BG: string = '#101318';
/** 默认前景色：贴近电脑终端的浅灰（用户要求与 PC 端观感一致，不再使用品牌浅绿）。 */
const TERMINAL_FG: string = '#E0E0E0';
const TERMINAL_DIM: string = '#7F7F7F';
const TERMINAL_FONT_SIZE: number = 12;
const TERMINAL_LINE_HEIGHT: number = 16;
// ponytail: 字体度量与设备实际列宽存在约两列误差；多设备实测不一致时再改为设备校准值。
const PTY_COL_SAFETY: number = 2;
const TERMINAL_PADDING_HORIZONTAL: number = 12;
const TERMINAL_PADDING_TOP: number = 12;
const IME_SENTINEL: string = '\u200B';
/** 终端等宽字体：保证字符宽度一致，列数才能按显示宽度精确换算。 */
const TERMINAL_FONT: string = 'monospace';
const REMOTE_WHEEL_THRESHOLD: number = 28;
const REMOTE_WHEEL_MAX_STEPS: number = 4;
const REMOTE_PAGE_WHEEL_STEPS: number = 8;

interface TerminalSegment {
  key: string;
  text: string;
  /** 文本样式：''=默认主题，'normal'=显式配色，'dim'=弱化，'inverse'=反色。 */
  style: string;
  foreground?: string;
  background?: string;
}

/** 逐字符渲染单元：含宽字符的段会被拆成单字符 Span，宽字符需额外补偿宽度。 */
interface CharUnit {
  key: string;
  text: string;
  /** 是否宽字符（占 2 列）。 */
  wide: boolean;
  /** 该字符的 letterSpacing 补偿（vp），不足 2 列的宽字符补正差值，已达标/超宽为 0。 */
  spacing: number;
}

/** 背景色块（vp 单位，按 行高×列宽 对齐）。 */
interface BgRect {
  key: string;
  x: number;
  y: number;
  w: number;
  color: string;
}

/** 背景层：一屏的背景色块 + 层高度。 */
interface BgLayer {
  rects: BgRect[];
  height: number;
}

// 鸿蒙物理键盘键值（对齐蓝本 App.kt 的 HARMONY_KEYCODE_* 常量）
const KEYCODE_ENTER: number = 2054;
const KEYCODE_BACKSPACE: number = 2055;
const KEYCODE_TAB: number = 2049;
const KEYCODE_ESC: number = 2070;
const KEYCODE_FORWARD_DEL: number = 2071;
const KEYCODE_UP: number = 2012;
const KEYCODE_DOWN: number = 2013;
const KEYCODE_LEFT: number = 2014;
const KEYCODE_RIGHT: number = 2015;
const KEYCODE_PGUP: number = 2068;
const KEYCODE_PGDN: number = 2069;
const KEYCODE_HOME: number = 2081;
const KEYCODE_END: number = 2082;

@Component
export struct TerminalNativeView {
  @Prop sessionId: number = -1;
  @Prop @Watch('onConnectedChange') connected: boolean = false;
  @Prop controlLocked: boolean = false;
  @Prop altLocked: boolean = false;
  controller: TerminalViewController = new TerminalViewController();
  onInput: (data: string) => void = () => {};
  onResize: (cols: number, rows: number) => void = () => {};

  @State output: string = '';
  @State imeText: string = IME_SENTINEL;
  @State previewText: string = '';
  @State cursorVisible: boolean = true;
  /** 远端终端光标在 output 快照中的 UTF-16 偏移（Rust 上报）。备用屏 TUI 模式下为真实输入位置，
   *  本地输入与闪烁光标插入该处；主屏模式为快照末尾（等价追加在提示符后）。 */
  @State cursorOffset: number = -1;
  @State styles: TerminalStyleRange[] = [];
  /** 仅工具条主动请求键盘期间开启；普通点击终端内容仍只聚焦、不弹软键盘。 */
  @State keyboardOnFocusEnabled: boolean = false;

  private inputController: TextInputController = new TextInputController();
  private scroller: Scroller = new Scroller();
  private cursorTimer: number = -1;
  private viewportFollowTimer: number = -1;
  private lastSendTime: number = 0;
  private lastCols: number = 0;
  private lastRows: number = 0;
  /** 等宽字体单字符宽度（vp），首次测量后缓存，用于把显示宽度精确换算成终端列数。 */
  private charWidthVp: number = 0;
  private followOutput: boolean = true;
  private pendingAutoScroll: boolean = false;
  private pendingKeyboardShow: boolean = false;
  private hiddenInputFocused: boolean = false;
  private mouseProtocol: TerminalMouseProtocol = 'none';
  private remotePanOffsetY: number = 0;
  private remoteWheelRemainder: number = 0;

  private eventListener: (ev: TmEvent) => void = (ev: TmEvent) => {
    if (ev.sessionId !== this.sessionId || ev.type !== 'output') {
      return;
    }
    // 契约：output 事件携带完整文本快照，整体替换即可
    this.output = ev.data ?? '';
    // 终端光标偏移：缺省时退回快照末尾（旧主屏行为）
    this.cursorOffset = ev.cursor !== undefined ? ev.cursor : -1;
    this.styles = ev.styles ?? [];
    const nextMouseProtocol = ev.mouseProtocol ?? 'none';
    if (nextMouseProtocol !== this.mouseProtocol) {
      hilog.info(DOMAIN, TAG, '终端鼠标协议变化: session=%{public}d protocol=%{public}s',
        this.sessionId, nextMouseProtocol);
      this.mouseProtocol = nextMouseProtocol;
    }
    this.pendingAutoScroll = this.followOutput;
  };

  aboutToAppear(): void {
    addEventListener(this.eventListener);
    // 光标闪烁，对齐蓝本的 infiniteRepeatable(500ms)
    this.cursorTimer = setInterval(() => this.cursorVisible = !this.cursorVisible, 500);
    this.controller.handleToolKey = (key: ToolbarKey) => this.onToolKey(key);
    this.controller.paste = (text: string) => {
      this.onInput(encodeKey(text, this.controlLocked, this.altLocked));
    };
    this.controller.focus = () => {
      // 页面切换后 ArkUI 的 onBlur 可能未及时同步，hiddenInputFocused 仍为 true，
      // 但 IME client 已 detached。先主动清焦，再在下一帧重新聚焦隐藏输入框。
      this.pendingKeyboardShow = false;
      this.hiddenInputFocused = false;
      this.keyboardOnFocusEnabled = true;
      try {
        this.getUIContext().getFocusController().clearFocus();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, '清除旧输入焦点失败: %{public}s', JSON.stringify(err));
      }
      setTimeout(() => {
        this.pendingKeyboardShow = true;
        void requestKeyboardFocus((inputId: string) =>
          focusControl.requestFocus(inputId), undefined, this.inputFocusId()).then(() => {
          // 已聚焦时 requestFocus 不一定再次触发 onFocus；给 IME client 留出 attach 时间后补一次显示请求。
          setTimeout(() => {
            if (this.pendingKeyboardShow) {
              this.pendingKeyboardShow = false;
              void this.showSoftKeyboard();
            }
          }, 100);
          // 恢复普通终端点击仅聚焦的约定；已弹出的键盘不受该属性回切影响。
          setTimeout(() => this.keyboardOnFocusEnabled = false, 500);
        });
      }, 50);
    };
    this.controller.blur = async () => {
      this.pendingKeyboardShow = false;
      this.hiddenInputFocused = false;
      this.keyboardOnFocusEnabled = false;
      try {
        this.getUIContext().getFocusController().clearFocus();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, '收起键盘时清除焦点失败: %{public}s', JSON.stringify(err));
      }
      try {
        await inputMethod.getController().hideTextInput();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, '隐藏软键盘失败: %{public}s', err.message);
      }
    };
  }

  aboutToDisappear(): void {
    removeEventListener(this.eventListener);
    clearInterval(this.cursorTimer);
    if (this.viewportFollowTimer !== -1) {
      clearTimeout(this.viewportFollowTimer);
      this.viewportFollowTimer = -1;
    }
  }

  /** Stack 会同时保留普通终端与 MUX 终端，焦点 ID 必须按 SSH 会话唯一。
   *  否则导航后的 requestFocus 会命中已隐藏的普通终端输入框。 */
  private inputFocusId(): string {
    return terminalInputFocusId(this.sessionId);
  }

  /** 连接建立后立即用已测得的真实行列数同步 PTY（连接时用的是预设 100x32，
   *  onTerminalAreaChange 在 connected 前触发只保存不发送）。 */
  private onConnectedChange(): void {
    if (this.connected && this.lastCols > 0 && this.lastRows > 0) {
      this.onResize(this.lastCols, this.lastRows);
    }
  }

  // ------------------------------------------------------------------
  // 输入处理
  // ------------------------------------------------------------------

  /** 回车直接发远端；普通字符已在 IME 提交时逐批发送。 */
  private sendInput(): void {
    // 防止 onKeyPreIme + onSubmit 双触发（软键盘 Send 键两条路径都调 sendInput）
    const now = Date.now();
    if (now - this.lastSendTime < 300) {
      return;
    }
    this.lastSendTime = now;
    this.onInput('\r');
    this.resetImeInput();
    // 发送动作后 IME 默认收起键盘，终端需要连续输入，立即夺回焦点保持键盘
    focusControl.requestFocus(this.inputFocusId());
  }

  /** onChange 只同步预上屏文字；正式提交由 onDidInsert 单独转发。 */
  private onInputChange(value: string, preview?: PreviewText): void {
    this.imeText = value;
    this.previewText = preview?.value ?? '';
  }

  /** 系统输入法确认提交后才发送，避免英文联想/中文组词的中间态重复上屏。 */
  private onImeInsert(info: InsertValue): void {
    if (info.insertValue.length > 0) {
      this.onInput(encodeKey(info.insertValue, this.controlLocked, this.altLocked));
    }
    this.resetImeInput();
  }

  /** 隐藏输入框只有一个哨兵；删除它等价于对远端当前光标发送一次退格。 */
  private onImeDelete(_info: DeleteValue): void {
    this.onInput(encodeKey('BACKSPACE', this.controlLocked, this.altLocked));
    this.resetImeInput();
  }

  private resetImeInput(): void {
    this.previewText = '';
    this.imeText = IME_SENTINEL;
    setTimeout(() => this.inputController.caretPosition(IME_SENTINEL.length), 0);
  }

  /** 工具条按键分发（CTRL/ALT/KBD/PAST 由 TerminalPage 处理，不会到这里）。 */
  private onToolKey(key: ToolbarKey): void {
    switch (key) {
      case '/':
      case '-':
      case ':':
      case '*':
      case '|':
        this.onInput(encodeKey(key, this.controlLocked, this.altLocked));
        return;
      case 'HOME':
        this.onInput(encodeKey('HOME', this.controlLocked, this.altLocked));
        return;
      case 'END':
        this.onInput(encodeKey('END', this.controlLocked, this.altLocked));
        return;
      case 'LEFT':
        this.onInput(encodeKey('LEFT', this.controlLocked, this.altLocked));
        return;
      case 'RIGHT':
        this.onInput(encodeKey('RIGHT', this.controlLocked, this.altLocked));
        return;
      case 'UP':
        this.onInput(encodeKey('UP', this.controlLocked, this.altLocked));
        return;
      case 'DOWN':
        this.onInput(encodeKey('DOWN', this.controlLocked, this.altLocked));
        return;
      case 'PGUP':
        this.pageScroll('up');
        break;
      case 'PGDN':
        this.pageScroll('down');
        break;
      case 'DEL':
        this.onInput(encodeKey('DEL', this.controlLocked, this.altLocked));
        return;
      case 'ESC':
        this.onInput(encodeKey('ESC', this.controlLocked, this.altLocked));
        return;
      case 'TAB':
        this.onInput(encodeKey('TAB', this.controlLocked, this.altLocked));
        return;
    }
  }

  private async showSoftKeyboard(): Promise<void> {
    await inputMethod.getController().showTextInput(inputMethod.RequestKeyboardReason.TOUCH).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, '显示软键盘失败: %{public}s', err.message);
    });
  }

  private pageScroll(direction: TerminalWheelDirection): void {
    if (this.mouseProtocol !== 'none') {
      this.sendRemoteWheel(direction, REMOTE_PAGE_WHEEL_STEPS);
      return;
    }
    this.scroller.scrollBy(0, direction === 'up' ? -300 : 300);
  }

  private sendRemoteWheel(direction: TerminalWheelDirection, steps: number, column?: number, row?: number): void {
    const targetColumn = column ?? Math.max(1, Math.floor(this.lastCols / 2));
    const targetRow = row ?? Math.max(1, Math.floor(this.lastRows / 2));
    const data = encodeTerminalWheel(this.mouseProtocol, direction, targetColumn, targetRow, steps);
    if (data.length > 0) {
      this.onInput(data);
    }
  }

  private beginRemotePan(event: GestureEvent): void {
    this.remotePanOffsetY = event.offsetY;
    this.remoteWheelRemainder = 0;
  }

  private updateRemotePan(event: GestureEvent): void {
    if (this.mouseProtocol === 'none') {
      return;
    }
    const deltaY = event.offsetY - this.remotePanOffsetY;
    this.remotePanOffsetY = event.offsetY;
    const batch = consumeTerminalWheelDelta(
      this.remoteWheelRemainder, deltaY, REMOTE_WHEEL_THRESHOLD, REMOTE_WHEEL_MAX_STEPS);
    this.remoteWheelRemainder = batch.remainder;
    if (batch.steps === 0) {
      return;
    }

    let column = Math.max(1, Math.floor(this.lastCols / 2));
    let row = Math.max(1, Math.floor(this.lastRows / 2));
    if (event.fingerList.length > 0) {
      column = Math.floor((event.fingerList[0].localX - TERMINAL_PADDING_HORIZONTAL) /
        this.measureCharWidthVp()) + 1;
      row = Math.floor((event.fingerList[0].localY - TERMINAL_PADDING_TOP) /
        TERMINAL_LINE_HEIGHT) + 1;
    }
    this.sendRemoteWheel(batch.direction, batch.steps,
      Math.max(1, Math.min(this.lastCols, column)), Math.max(1, Math.min(this.lastRows, row)));
  }

  /** 终端光标偏移（钳到 output 范围内）；缺省（-1）取末尾，等价主屏追加。 */
  private terminalCursorOffset(): number {
    if (this.cursorOffset < 0) {
      return this.output.length;
    }
    return Math.max(0, Math.min(this.cursorOffset, this.output.length));
  }

  /** 预编辑期间隐藏光标后同一行的 PlaceHolder，下一行及后续画面继续显示。 */
  private visibleAfterCursorStart(): number {
    const cursor = this.terminalCursorOffset();
    if (this.previewText.length === 0) {
      return cursor;
    }
    const newline = this.output.indexOf('\n', cursor);
    return newline >= 0 ? newline : this.output.length;
  }

  /** 光标处的字符（含代理对/宽字符），光标在末尾时为空串。 */
  private cursorChar(): string {
    const cursor = this.terminalCursorOffset();
    if (cursor >= this.output.length) {
      return '';
    }
    const code = this.output.codePointAt(cursor) ?? 0;
    return code > 0xFFFF ? this.output.substring(cursor, cursor + 2) : this.output.substring(cursor, cursor + 1);
  }

  /** 光标后内容的起始偏移：跳过光标字符（文字不增删），预编辑时仍按行隐藏。 */
  private afterCursorStart(): number {
    if (this.previewText.length > 0) {
      return this.visibleAfterCursorStart();
    }
    const cursor = this.terminalCursorOffset();
    return cursor + terminalCursorCharSkip(this.cursorChar());
  }

  /** 判断字符是否为终端宽字符（占 2 列）：CJK 全角。与 Rust unicode-width 规则对齐。 */
  private isWideChar(code: number): boolean {
    return (code >= 0x1100 && code <= 0x115F) ||   // Hangul Jamo
      (code >= 0x2E80 && code <= 0xA4CF) ||        // CJK 部首/假名/汉字等
      (code >= 0xAC00 && code <= 0xD7A3) ||        // Hangul 音节
      (code >= 0xF900 && code <= 0xFAFF) ||        // CJK 兼容汉字
      (code >= 0xFE30 && code <= 0xFE70) ||        // CJK 兼容形式/全角
      (code >= 0xFF00 && code <= 0xFF60) ||        // 全角 ASCII
      (code >= 0x20000 && code <= 0x3FFFD);        // CJK 扩展 B+
  }

  /** 分段是否含宽字符（含则需逐字符渲染并补偿宽度以对齐）。 */
  private hasWide(text: string): boolean {
    for (let i = 0; i < text.length; i++) {
      const code = text.codePointAt(i) ?? 0;
      if (code > 0xFFFF || this.isWideChar(code)) {
        return true;
      }
    }
    return false;
  }

  /** 将快照区间按 Rust 上报的样式（弱化/反色）切为 Span。 */
  private segmentsBetween(start: number, end: number): TerminalSegment[] {
    const from = Math.max(0, Math.min(start, this.output.length));
    const to = Math.max(from, Math.min(end, this.output.length));
    const result: TerminalSegment[] = [];
    let position = from;
    this.styles.forEach((range: TerminalStyleRange) => {
      const rangeStart = Math.max(from, Math.min(range.start, to));
      const rangeEnd = Math.max(rangeStart, Math.min(range.end, to));
      if (rangeEnd <= position) {
        return;
      }
      if (rangeStart > position) {
        result.push({
          key: `${position}-${rangeStart}-normal`,
          text: this.output.substring(position, rangeStart),
          style: '',
        });
      }
      const segStart = Math.max(position, rangeStart);
      result.push({
        key: `${segStart}-${rangeEnd}-${range.style}-${range.foreground ?? ''}-${range.background ?? ''}`,
        text: this.output.substring(segStart, rangeEnd),
        style: range.style,
        foreground: range.foreground,
        background: range.background,
      });
      position = rangeEnd;
    });
    if (position < to) {
      result.push({
        key: `${position}-${to}-normal`,
        text: this.output.substring(position, to),
        style: '',
      });
    }
    return result;
  }

  /** 分段前景色：显式 ANSI 色优先，反色在解析后的前景/背景上互换。
   *  背景不由 Span 承担（宽字符背景盒按 CJK 回退字体度量收缩会露黑缝），统一由 bgLayer 色块层绘制。 */
  private segmentFg(part: TerminalSegment): string {
    const foreground = part.foreground ?? (part.style === 'dim' ? TERMINAL_DIM : TERMINAL_FG);
    const background = part.background ?? TERMINAL_BG;
    return part.style === 'inverse' ? background : foreground;
  }

  /** 样式范围对应的背景色（与 segmentFg 的反色互换规则一致）；无背景返回 null。 */
  private rangeBgColor(range: TerminalStyleRange): string | null {
    if (range.style === 'inverse') {
      return range.foreground ?? TERMINAL_FG;
    }
    return range.background !== undefined ? (range.background ?? TERMINAL_BG) : null;
  }

  /** 由输出快照与样式范围计算整屏背景色块（行高 × 列宽对齐的单趟扫描），
   *  替代 Span textBackgroundStyle：宽字符 Span 的背景盒按 CJK 回退字体度量收缩，
   *  色块顶/底会露出黑缝（tmux 状态栏 "8月-26" 的"下划线"实为该缝隙）。 */
  private bgLayer(): BgLayer {
    const cw = this.measureCharWidthVp();
    const lh = TERMINAL_LINE_HEIGHT;
    const rects: BgRect[] = [];
    const text = this.output;
    const ranges = this.styles.slice().sort((a, b) => a.start - b.start);
    let rangeIdx = 0;
    let color: string | null = null;
    let runStartCol = -1;
    let row = 0;
    let col = 0;
    const closeRun = () => {
      if (color !== null && runStartCol >= 0 && col > runStartCol) {
        rects.push({
          key: `r${row}-c${runStartCol}-${rects.length}`,
          x: runStartCol * cw,
          y: row * lh,
          w: (col - runStartCol) * cw,
          color: color ?? '',
        });
      }
      runStartCol = -1;
    };
    let i = 0;
    while (i < text.length) {
      if (text.charCodeAt(i) === 0x0A) { // '\n'
        closeRun();
        color = null;
        row++;
        col = 0;
        i++;
        continue;
      }
      while (rangeIdx < ranges.length && ranges[rangeIdx].end <= i) {
        rangeIdx++;
      }
      const c = rangeIdx < ranges.length && ranges[rangeIdx].start <= i
        ? this.rangeBgColor(ranges[rangeIdx]) : null;
      if (c !== color) {
        closeRun();
        color = c;
        if (c !== null) {
          runStartCol = col;
        }
      }
      const code = text.codePointAt(i) ?? 0;
      if (code > 0xFFFF) {
        col += 2; // 代理对（emoji/扩展汉字）按宽字符，与 splitChars 一致
        i += 2;
      } else {
        col += this.isWideChar(code) ? 2 : 1;
        i++;
      }
    }
    closeRun();
    return { rects, height: (row + 1) * lh };
  }

  /** 实测单个字符的渲染宽度（vp），带缓存避免重复测量。 */
  private charWidthCache: Map<string, number> = new Map();

  private measureCharVp(ch: string): number {
    const cached = this.charWidthCache.get(ch);
    if (cached !== undefined) {
      return cached;
    }
    let w = 0;
    try {
      const sz = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: ch, fontSize: TERMINAL_FONT_SIZE, fontFamily: TERMINAL_FONT });
      const px = typeof sz.width === 'number' ? sz.width : Number(sz.width);
      w = px2vp(px);
    } catch (err) {
      w = 0;
    }
    this.charWidthCache.set(ch, w);
    return w;
  }

  /** 计算宽字符的 letterSpacing 补偿（vp）：把该字实际宽度补到 2 列；已达标或超宽（emoji）不补。 */
  private wideCharSpacingFor(ch: string): number {
    const target = 2 * this.measureCharWidthVp();
    const actual = this.measureCharVp(ch);
    const shortage = target - actual;
    return shortage > 0 ? shortage : 0;
  }

  /** 把含宽字符的段拆成逐字符渲染单元（代理对合并为一个字符）。 */
  private splitChars(part: TerminalSegment): CharUnit[] {
    const units: CharUnit[] = [];
    let i = 0;
    let idx = 0;
    const text = part.text;
    while (i < text.length) {
      const code = text.codePointAt(i) ?? 0;
      let ch: string;
      let wide: boolean;
      if (code > 0xFFFF) {
        ch = text.substring(i, i + 2); // 代理对
        i += 2;
        wide = true; // emoji/扩展汉字按宽字符
      } else {
        ch = text.substring(i, i + 1);
        i += 1;
        wide = this.isWideChar(code);
      }
      units.push({ key: `${part.key}-c${idx}`, text: ch, wide, spacing: wide ? this.wideCharSpacingFor(ch) : 0 });
      idx++;
    }
    return units;
  }

  /** 测量等宽字体单字符宽度（vp）。终端列数按此精确换算，
   *  使远端按 PTY 列宽绘制的行恰好贴合显示宽度，避免显示层二次换行。 */
  private measureCharWidthVp(): number {
    if (this.charWidthVp > 0) {
      return this.charWidthVp;
    }
    try {
      const sizePx = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: 'M'.repeat(100),
        fontSize: TERMINAL_FONT_SIZE,
        fontFamily: TERMINAL_FONT,
      });
      const w = sizePx.width;
      const widthPx = typeof w === 'number' ? w : Number(w);
      if (widthPx > 0) {
        this.charWidthVp = px2vp(widthPx) / 100;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '测量字宽失败，回退估算: %{public}s', JSON.stringify(err));
    }
    if (this.charWidthVp <= 0) {
      // 等宽字体约 0.6em；取宽值避免高估列数导致换行
      this.charWidthVp = 7.2;
    }
    return this.charWidthVp;
  }

  /** 键盘避让会先改变 Scroll 视口，再完成整棵布局；延迟到布局稳定后滚底。
   *  仅在尺寸变化前本来就在跟随最新输出时调用，不打断用户主动上翻历史。 */
  private scheduleViewportFollow(): void {
    if (this.viewportFollowTimer !== -1) {
      clearTimeout(this.viewportFollowTimer);
    }
    this.viewportFollowTimer = setTimeout(() => {
      // 用户真实拖动会由 onTouch(Move) 调用 pauseOutputFollow 并取消本定时器；
      // 这里不能再次检查 followOutput，因为布局压缩产生的 onDidScroll 也可能
      // 暂时把它置为 false，导致键盘弹出后错误停在旧的顶部位置。
      this.scroller.scrollEdge(Edge.Bottom);
      this.viewportFollowTimer = -1;
    }, 80);
  }

  /** 用户开始滚动时立即退出自动跟随，并废弃已经排队的滚底任务。 */
  private pauseOutputFollow(): void {
    this.followOutput = false;
    this.pendingAutoScroll = false;
    if (this.viewportFollowTimer !== -1) {
      clearTimeout(this.viewportFollowTimer);
      this.viewportFollowTimer = -1;
    }
  }

  /** 终端区域尺寸变化 → 估算行列数并保存，经 onResize 交父级同步 PTY（父级按连接态门控）。 */
  private onTerminalAreaChange(oldArea: Area, area: Area): void {
    const width = area.width as number;
    const height = area.height as number;
    const oldHeight = oldArea.height as number;
    if (height !== oldHeight && this.followOutput) {
      this.scheduleViewportFollow();
    }
    // 底部不留内边距，PTY 按真实文本高度铺满终端视口，避免状态栏下方空出一行。
    const availWidth = Math.max(0, width - TERMINAL_PADDING_HORIZONTAL * 2);
    const availHeight = Math.max(0, height - TERMINAL_PADDING_TOP);
    const cols = Math.max(20, Math.floor(availWidth / this.measureCharWidthVp()) - PTY_COL_SAFETY);
    const rows = Math.max(5, Math.floor(availHeight / TERMINAL_LINE_HEIGHT));
    if (cols === this.lastCols && rows === this.lastRows) {
      return;
    }
    this.lastCols = cols;
    this.lastRows = rows;
    this.onResize(cols, rows);
  }

  /** 硬件按键预处理（IME 之前）：特殊键直接编码发远端，字符键放行给隐藏输入框。 */
  private onHardwareKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    const ctrl = this.controlLocked || this.physModifier(event, 'ctrl');
    const alt = this.altLocked || this.physModifier(event, 'alt');
    switch (event.keyCode) {
      case KEYCODE_ENTER:
        this.sendInput();
        return true;
      case KEYCODE_TAB:
        this.onInput(encodeKey('TAB', ctrl, alt));
        return true;
      case KEYCODE_ESC:
        this.onInput(encodeKey('ESC', ctrl, alt));
        return true;
      case KEYCODE_FORWARD_DEL:
        this.onToolKey('DEL');
        return true;
      case KEYCODE_UP:
        this.onInput(encodeKey('UP', ctrl, alt));
        return true;
      case KEYCODE_DOWN:
        this.onInput(encodeKey('DOWN', ctrl, alt));
        return true;
      case KEYCODE_LEFT:
        this.onToolKey('LEFT');
        return true;
      case KEYCODE_RIGHT:
        this.onToolKey('RIGHT');
        return true;
      case KEYCODE_HOME:
        this.onToolKey('HOME');
        return true;
      case KEYCODE_END:
        this.onToolKey('END');
        return true;
      case KEYCODE_PGUP:
        this.pageScroll('up');
        return true;
      case KEYCODE_PGDN:
        this.pageScroll('down');
        return true;
      case KEYCODE_BACKSPACE:
        this.onInput(encodeKey('BACKSPACE', ctrl, alt));
        return true;
      default:
        // 可打印字符放行给隐藏输入框（经 onChange 进入本地缓冲或编码发送）
        return false;
    }
  }

  /** 读取物理修饰键状态（API 为可选方法 + 字符串参数，版本差异兜底为 false）。 */
  private physModifier(event: KeyEvent, which: 'ctrl' | 'alt'): boolean {
    try {
      return event.getModifierKeyState?.([which]) ?? false;
    } catch {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  build() {
    Column() {
      // 终端容器：黑底绿字，内部为可滚动输出快照 + 行内输入（光标位于真实提示词后）
      Column() {
        // 输出区：远端快照 + 行内输入合并到同一 Text，可滚动。
        // 本地输入与闪烁光标插入在远端终端光标偏移处（cursorOffset）：
        // 主屏模式偏移=快照末尾 → 追加在提示符后（与真实终端一致）；
        // 备用屏 TUI 模式偏移=真实光标位置 → 光标闪烁在 TUI 输入框等待输入处，画面其余部分续在其后
        Scroll(this.scroller) {
          Stack() {
            // 背景色块层：替代 Span textBackgroundStyle（宽字符背景盒收缩露黑缝），
            // 色块按 行高×列宽 对齐铺满，Text 层只画文字（内容 Span 背景全透明）。
            Stack() {
              ForEach(this.bgLayer().rects, (r: BgRect) => {
                Row()
                  .position({ x: r.x, y: r.y })
                  .width(r.w)
                  .height(TERMINAL_LINE_HEIGHT)
                  .backgroundColor(r.color)
              }, (r: BgRect) => r.key)
            }
            .width('100%')
            .height(this.bgLayer().height)

            Text() {
            // 光标前内容
            ForEach(this.segmentsBetween(0, this.terminalCursorOffset()), (part: TerminalSegment) => {
              if (this.hasWide(part.text)) {
                // 含宽字符：逐字符渲染，宽字符加 letterSpacing 补足到 2 列对齐
                ForEach(this.splitChars(part), (u: CharUnit) => {
                  Span(u.text)
                    .fontColor(this.segmentFg(part))
                    .letterSpacing(u.spacing)
                }, (u: CharUnit) => u.key)
              } else {
                Span(part.text)
                  .fontColor(this.segmentFg(part))
              }
            }, (part: TerminalSegment) => part.key)
            Span(this.previewText)
            // 覆盖式光标：光标处字符反色闪烁，文字完全不增删、零挤压。
            // 光标在末尾（无字符）或落在空格上时，空格反色不可见，改用 ▌ 块闪烁。
            if (this.cursorChar().length > 0 && this.cursorChar().trim().length > 0) {
              Span(this.cursorChar())
                .fontColor(this.cursorVisible ? TERMINAL_BG : TERMINAL_FG)
                .textBackgroundStyle({ color: this.cursorVisible ? TERMINAL_FG : '#00E0E0E0' })
                .letterSpacing(this.hasWide(this.cursorChar()) ? this.wideCharSpacingFor(this.cursorChar()) : 0)
            } else {
              Span('▌')
                .fontColor(this.cursorVisible ? TERMINAL_FG : '#00E0E0E0')
            }
            // 光标后内容（从光标字符之后开始；预编辑时按行隐藏）
            ForEach(this.segmentsBetween(this.afterCursorStart(), this.output.length),
              (part: TerminalSegment) => {
                if (this.hasWide(part.text)) {
                  ForEach(this.splitChars(part), (u: CharUnit) => {
                    Span(u.text)
                      .fontColor(this.segmentFg(part))
                      .letterSpacing(u.spacing)
                  }, (u: CharUnit) => u.key)
                } else {
                  Span(part.text)
                    .fontColor(this.segmentFg(part))
                }
              }, (part: TerminalSegment) => part.key)
          }
          .fontSize(TERMINAL_FONT_SIZE)
          .lineHeight(TERMINAL_LINE_HEIGHT)
          .fontFamily(TERMINAL_FONT)
          .fontColor(TERMINAL_FG)
          .width('100%')
          .textAlign(TextAlign.Start)
          // 布局完成后再滚底：事件回调里同步 scrollEdge 发生在新快照布局前，
          // 只到旧内容的底，新增行会落在视口外（对比 PC 时"最新内容显示不全"）
          .onAreaChange((_old: Area, _new: Area) => {
            if (this.pendingAutoScroll && this.followOutput) {
              this.scroller.scrollEdge(Edge.Bottom);
            }
            this.pendingAutoScroll = false;
          })
          }
          .alignContent(Alignment.TopStart)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollable(ScrollDirection.Vertical)
        .enableScrollInteraction(true)
        .onClick(() => focusControl.requestFocus(this.inputFocusId()))
        // 只把真实触摸拖动视为用户主动离开底部；窗口 RESIZE 造成的布局滚动也会
        // 触发 onScrollStart，不能因此取消键盘弹出后的自动滚底。
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Move) {
            this.pauseOutputFollow();
          }
        })
        .onDidScroll(() => {
          this.followOutput = this.scroller.isAtEnd();
        })
        .onScrollEdge((edge: Edge) => {
          if (edge === Edge.Bottom) {
            this.followOutput = true;
          }
        })
        // Scroll 自带单指 Pan 识别器；双指远端滚轮必须并行绑定，否则内置滚动会先抢占事件。
        .parallelGesture(
          PanGesture({ fingers: 2, direction: PanDirection.Vertical, distance: 5 })
            .onActionStart((event: GestureEvent) => this.beginRemotePan(event))
            .onActionUpdate((event: GestureEvent) => this.updateRemotePan(event))
        )
        // 内容贴顶对齐（行内光标已随提示词，不再需要贴底消除割裂感）；
        // 超一屏时对齐不影响滚动，scrollEdge(Bottom) 仍保证最新行可见
        .align(Alignment.Top)
        .padding({
          left: TERMINAL_PADDING_HORIZONTAL,
          right: TERMINAL_PADDING_HORIZONTAL,
          top: TERMINAL_PADDING_TOP,
          bottom: 0,
        })
        .onAreaChange((oldArea: Area, newArea: Area) => this.onTerminalAreaChange(oldArea, newArea))
      }
      .layoutWeight(1)
      .width('100%')
      .constraintSize({ minHeight: 320 })
      .backgroundColor(TERMINAL_BG)
      .borderRadius(8)
      .margin({ top: 6 })
      .clip(true)

      // 隐藏 1dp 输入框：仅用于唤起软键盘接收文本（对齐蓝本 BasicTextField 1dp alpha 0.01）
      // 绑定零宽哨兵：提交文字后立即复位，避免输入法持续积累整串英文；
      // 哨兵还让空终端上的软键盘退格产生可转发事件。
      // position 使其脱离 Column 布局流：TextInput 设 height(1) 实际仍占 ~56px，
      // 若参与排布会把工具条顶下去产生空白（重构前它挂在页面 Stack 重叠层，不占空间）
      TextInput({ text: this.imeText, controller: this.inputController })
        .id(this.inputFocusId())
        .position({ x: 0, y: 0 })
        .width(1)
        .height(1)
        .opacity(0.01)
        .enableKeyboardOnFocus(this.keyboardOnFocusEnabled)
        // 终端输入键盘类型选择（实测踩坑记录）：
        // - Normal：小艺输入法会对首字母自动大写（autoCapitalizationMode(NONE) 无效，命令被改错）
        // - Email：不大写但空格被吞（无法输入带空格的命令）
        // - Password：触发系统隐私保护，整个窗口截屏全黑（不可用）
        // - USER_NAME：不大写、不吞空格（当前采用）
        .type(InputType.USER_NAME)
        .enterKeyType(EnterKeyType.Send)
        .onFocus(() => {
          hilog.debug(DOMAIN, TAG, '隐藏输入框已聚焦，准备显示软键盘');
          this.hiddenInputFocused = true;
          this.inputController.caretPosition(this.imeText.length);
          if (this.pendingKeyboardShow) {
            this.pendingKeyboardShow = false;
            void this.showSoftKeyboard();
          }
        })
        .onBlur(() => {
          this.hiddenInputFocused = false;
          this.pendingKeyboardShow = false;
        })
        .onChange((value: string, preview?: PreviewText) => this.onInputChange(value, preview))
        .onDidInsert((info: InsertValue) => this.onImeInsert(info))
        .onDidDelete((info: DeleteValue) => this.onImeDelete(info))
        .onSubmit(() => this.sendInput())
        .onKeyPreIme((event: KeyEvent) => this.onHardwareKey(event))
    }
    .layoutWeight(1)
    .width('100%')
  }
}
