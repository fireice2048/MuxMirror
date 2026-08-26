/**
 * 终端键盘工具条：两行各 10 键，键位表对齐蓝本 App.kt 的 TERMINAL_TOOL_ROWS。
 * CTRL/ALT 为锁定态切换（绿底白字 + 下划线）；键盘图标控制软键盘开关。
 */

/** 工具条按键标识。 */
export type ToolbarKey =
  '/' | '-' | ':' | '*' | '|' | 'HOME' | 'UP' | 'END' | 'PGUP' | 'DEL' |
  'ESC' | 'TAB' | 'PAST' | 'CTRL' | 'ALT' | 'LEFT' | 'DOWN' | 'RIGHT' | 'PGDN' | 'KBD';

interface ToolbarKeyDef {
  key: ToolbarKey;
  label: string;
}

/** 键位表，与蓝本 App.kt:367-392 的 TERMINAL_TOOL_ROWS 一一对应。 */
const TOOL_ROWS: ToolbarKeyDef[][] = [
  [
    { key: '/', label: '/' }, { key: '-', label: '-' }, { key: ':', label: ':' },
    { key: '*', label: '*' }, { key: '|', label: '|' }, { key: 'HOME', label: 'HOME' },
    { key: 'UP', label: '↑' }, { key: 'END', label: 'END' }, { key: 'PGUP', label: 'PGUP' },
    { key: 'DEL', label: 'DEL' },
  ],
  [
    { key: 'ESC', label: 'ESC' }, { key: 'TAB', label: 'TAB' }, { key: 'PAST', label: 'PAST' },
    { key: 'CTRL', label: 'CTRL' }, { key: 'ALT', label: 'ALT' }, { key: 'LEFT', label: '←' },
    { key: 'DOWN', label: '↓' }, { key: 'RIGHT', label: '→' }, { key: 'PGDN', label: 'PGDN' },
    { key: 'KBD', label: '' },
  ],
];

const KEY_ACTIVE_BG: string = '#1F7A3D';
const KEY_NORMAL_BG: string = '#E6F4EA';

@Component
export struct TerminalToolbar {
  /** CTRL 锁定态。 */
  @Prop controlLocked: boolean = false;
  /** ALT 锁定态。 */
  @Prop altLocked: boolean = false;
  /** 按键回调。 */
  onKeyAction: (key: ToolbarKey) => void = () => {
  };

  private isChecked(key: ToolbarKey): boolean {
    return (key === 'CTRL' && this.controlLocked) || (key === 'ALT' && this.altLocked);
  }

  build() {
    Column({ space: 2 }) {
      ForEach(TOOL_ROWS, (row: ToolbarKeyDef[]) => {
        Row({ space: 2 }) {
          ForEach(row, (item: ToolbarKeyDef) => {
            Column() {
              if (item.key === 'KBD') {
                Image($r('app.media.keyboard_icon'))
                  .width(20)
                  .height(20)
                  .objectFit(ImageFit.Contain)
              } else {
                Text(item.label)
                  .fontSize(9)
                  .fontColor(this.isChecked(item.key) ? Color.White : KEY_ACTIVE_BG)
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  // CTRL/ALT 加下划线，对齐蓝本 TextDecoration.Underline
                  .decoration(item.key === 'CTRL' || item.key === 'ALT' ?
                    { type: TextDecorationType.Underline,
                      color: this.isChecked(item.key) ? Color.White : KEY_ACTIVE_BG } :
                    { type: TextDecorationType.None })
              }
            }
            .justifyContent(FlexAlign.Center)
            .height(32)
            .layoutWeight(1)
            .borderRadius(4)
            .backgroundColor(this.isChecked(item.key) ? KEY_ACTIVE_BG : KEY_NORMAL_BG)
            .onClick(() => this.onKeyAction(item.key))
          }, (item: ToolbarKeyDef) => item.key)
        }
        .width('100%')
      }, (row: ToolbarKeyDef[], index: number) => `row-${index}`)
    }
    .width('100%')
  }
}
