# 踩坑记忆：沉浸式全屏下底部导航横条高度要用 TYPE_NAVIGATION_INDICATOR 取

## 现象

- 触发条件：TermMirror 鸿蒙终端页工具条贴屏幕底部，被手势导航指示条（底部横条）遮挡，影响点击。
- 尝试用 `getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect.height` 取导航栏高度预留底部边距，结果该值在模拟器上恒为 0，边距没生效，按键依旧贴着底部横条。

## 根因

- 工程用了沉浸式全屏布局（`setWindowLayoutFullScreen(true)` + `setWindowSystemBarEnable(['status','navigation'])`），内容绘制延伸到导航栏底下，系统不再为导航栏预留避让区，因此 `TYPE_SYSTEM.bottomRect.height` 返回 0。
- 手势导航的指示条（底部横条）有独立的避让区类型 `window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR`（API 11+），其 `bottomRect.height` 才是指示条真实高度（本机模拟器约 32vp）。

## 正确做法

- 取底部避让高度时两个类型都读，取较大值，兼容三键导航（TYPE_SYSTEM 有值）与手势导航（TYPE_NAVIGATION_INDICATOR 有值）：

```ts
const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
const navIndicator = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
const bottomAvoidPx = Math.max(avoid.bottomRect.height, navIndicator.bottomRect.height);
AppStorage.setOrCreate('navigationBarHeight', px2vp(bottomAvoidPx));
```

- 页面侧用 `@StorageProp('navigationBarHeight')` 读取，作为工具条底部边距；软键盘升起（RESIZE 避让）后该边距收为 0，避免工具条离键盘过远。

## 关联坑：Stack 底部定位的叠加层要跟着边距走

- 安全粘贴叠加层（PasteButton）用 `Stack(Alignment.BottomStart)` + 固定 `bottom:2.4` 定位。给工具条加导航避让边距后工具条整体上移，粘贴按钮没跟着上移，掉进导航区（"粘贴按钮掉到底部"）。
- 修法：叠加层底部 padding 与工具条共用同一个 `toolbarBottomPadding()`，保证始终覆盖在工具条 PAST 键位置。
- 教训：任何相对屏幕底部绝对定位的元素，在引入底部动态边距后都要同步该边距，否则会与新上移的内容错位。

## 验证方式

- `uitest dumpLayout` 对比改动前后工具条第二行按键 bounds：底部边距生效后按键底边从 y=2848 上移到 y=2750（约 32vp 导航高度）；键盘升起后按键底部仅剩 2.4vp 基础边距。
- 截图确认底部横条位于屏幕最底部、工具条在其上方；PasteButton bounds 与 PAST 键 bounds 重合。
