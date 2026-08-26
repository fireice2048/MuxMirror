import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import {
  consumeTerminalWheelDelta, encodeTerminalWheel, requestKeyboardFocus, terminalCursorCharSkip,
  terminalInputFocusId
} from '../main/ets/components/TerminalDisplayContract';
import {
  CurrentValueEventSignal,
  EventSignal,
  EventSignalCancellable,
  EventSignalCancellableSet
} from '../main/ets/utilities/communication/EventSignal';
import {
  addEventListener,
  removeEventListener,
  TmEvent,
  tmEventSignal
} from '../main/ets/core/TermirrorCore';
import { buildMuxAttachCommand } from '../main/ets/pages/TerminalPage';
import { uniqueMuxTabs } from '../main/ets/pages/MuxNavPage';
import { NavTab } from '../main/ets/components/TerminalNavPanel';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });

    it('attaches only from a plain shell and never switches another tmux client', 0, () => {
      const command = buildMuxAttachCommand('TMUX', 'tab-14');

      expect(command).assertContain('if [ -n "${TMUX-}${RMUX_SESSION-}${RMUX-}" ]');
      expect(command).assertContain('_tm_tty=$(tty)');
      expect(command).assertContain('tmux refresh-client -D -t "$_tm_tty" 999');
      expect(command).assertContain("exec tmux attach-session -f ignore-size -t 'tab-14'");
      expect(command.indexOf('switch-client')).assertEqual(-1);
    });

    it('quotes rmux session names without generating a client switch', 0, () => {
      const command = buildMuxAttachCommand('RMUX', "team's tab");

      expect(command).assertContain('rmux refresh-client -D -t "$_tm_tty" 999');
      expect(command).assertContain("exec rmux attach-session -f ignore-size -t 'team'\"'\"'s tab'");
      expect(command.indexOf('switch-client')).assertEqual(-1);
    });

    it('deduplicates multiple attached clients for one mux session', 0, () => {
      const tabs: NavTab[] = [
        { title: 'desktop', active: true, mux: 'TMUX', session: 'tab-14', cwd: '~/Repo/TermHook' },
        { title: 'simulator', active: true, mux: 'TMUX', session: 'tab-14', cwd: '' },
        { title: 'device', active: true, mux: 'tmux', session: 'tab-14', cwd: '' },
        { title: 'other', active: true, mux: 'TMUX', session: 'tab-13', cwd: '~/Repo/TermHook' },
      ];

      const unique = uniqueMuxTabs(tabs);

      expect(unique.length).assertEqual(2);
      expect(unique[0].session).assertEqual('tab-14');
      expect(unique[1].session).assertEqual('tab-13');
    });

    it('requests focus before showing the soft keyboard', 0, async () => {
      const calls: string[] = [];
      await requestKeyboardFocus(
        () => calls.push('focus'),
        (task: () => void) => {
          calls.push('schedule');
          task();
        }
      );

      expect(calls.join(',')).assertEqual('focus,schedule');
    });

    it('uses a unique terminal input focus id for each session', 0, () => {
      expect(terminalInputFocusId(1)).assertEqual('tmHiddenInput-1');
      expect(terminalInputFocusId(2)).assertEqual('tmHiddenInput-2');
      expect(terminalInputFocusId(1) === terminalInputFocusId(2)).assertFalse();
    });

    it('preserves a newline under the terminal cursor', 0, () => {
      expect(terminalCursorCharSkip('\n')).assertEqual(0);
      expect(terminalCursorCharSkip(' ')).assertEqual(1);
      expect(terminalCursorCharSkip('中')).assertEqual(1);
      expect(terminalCursorCharSkip('😀')).assertEqual(2);
    });

    it('encodes SGR and X10 terminal wheel events with clamped coordinates', 0, () => {
      expect(encodeTerminalWheel('sgr', 'up', 12, 7)).assertEqual('\x1B[<64;12;7M');
      expect(encodeTerminalWheel('sgr', 'down', -2, 0)).assertEqual('\x1B[<65;1;1M');
      expect(encodeTerminalWheel('x10', 'up', 1, 1)).assertEqual('\x1B[M`!!');
      expect(encodeTerminalWheel('none', 'up', 1, 1)).assertEqual('');
    });

    it('converts two finger movement into bounded remote wheel steps', 0, () => {
      const pending = consumeTerminalWheelDelta(0, 20, 28, 4);
      expect(pending.steps).assertEqual(0);
      expect(pending.remainder).assertEqual(20);

      const upward = consumeTerminalWheelDelta(pending.remainder, 40, 28, 4);
      expect(upward.direction).assertEqual('up');
      expect(upward.steps).assertEqual(2);
      expect(upward.remainder).assertEqual(4);

      const bounded = consumeTerminalWheelDelta(0, -300, 28, 4);
      expect(bounded.direction).assertEqual('down');
      expect(bounded.steps).assertEqual(4);
      expect(bounded.remainder).assertEqual(-20);
    });

    it('broadcasts a typed value to every retained subscriber', 0, () => {
      const signal: EventSignal<number> = new EventSignal<number>();
      const cancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const received: string[] = [];

      signal.on((value: number) => received.push(`first:${value}`)).into(cancellables);
      signal.on((value: number) => received.push(`second:${value}`)).into(cancellables);
      signal.send(7);

      expect(received.join(',')).assertEqual('first:7,second:7');
      expect(signal.subscriberCount).assertEqual(2);
      expect(cancellables.count).assertEqual(2);
    });

    it('cancels one subscription idempotently', 0, () => {
      const signal: EventSignal<string> = new EventSignal<string>();
      const cancellable: EventSignalCancellable = signal.on((_value: string) => {
        throw new Error('取消后的订阅不应执行');
      });

      cancellable.cancel();
      cancellable.cancel();
      signal.send('ignored');

      expect(cancellable.isCancelled).assertTrue();
      expect(signal.subscriberCount).assertEqual(0);
    });

    it('cancels and clears a cancellable set', 0, () => {
      const signal: EventSignal<number> = new EventSignal<number>();
      const cancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const received: number[] = [];

      signal.on((value: number) => received.push(value)).into(cancellables);
      signal.on((value: number) => received.push(value * 10)).into(cancellables);
      cancellables.cancelAll();
      cancellables.cancelAll();
      signal.send(3);

      expect(received.length).assertEqual(0);
      expect(signal.subscriberCount).assertEqual(0);
      expect(cancellables.count).assertEqual(0);
    });

    it('replays the latest current value to new subscribers', 0, () => {
      const signal: CurrentValueEventSignal<number> = new CurrentValueEventSignal<number>(1);
      const firstCancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const secondCancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const firstReceived: number[] = [];
      const secondReceived: number[] = [];

      signal.on((value: number) => firstReceived.push(value)).into(firstCancellables);
      signal.send(2);
      signal.on((value: number) => secondReceived.push(value)).into(secondCancellables);

      expect(firstReceived.join(',')).assertEqual('1,2');
      expect(secondReceived.join(',')).assertEqual('2');
      expect(signal.value).assertEqual(2);
    });

    it('resets the current value without notifying existing subscribers', 0, () => {
      const signal: CurrentValueEventSignal<string> =
        new CurrentValueEventSignal<string>('initial');
      const existingCancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const laterCancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const existingReceived: string[] = [];
      const laterReceived: string[] = [];

      signal.on((value: string) => existingReceived.push(value)).into(existingCancellables);
      signal.resetCurrentValue('reset');
      signal.on((value: string) => laterReceived.push(value)).into(laterCancellables);

      expect(existingReceived.join(',')).assertEqual('initial');
      expect(laterReceived.join(',')).assertEqual('reset');
      expect(signal.value).assertEqual('reset');
    });

    it('keeps separate signal instances isolated', 0, () => {
      const firstSignal: EventSignal<number> = new EventSignal<number>();
      const secondSignal: EventSignal<number> = new EventSignal<number>();
      const cancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const firstReceived: number[] = [];
      const secondReceived: number[] = [];

      firstSignal.on((value: number) => firstReceived.push(value)).into(cancellables);
      secondSignal.on((value: number) => secondReceived.push(value)).into(cancellables);
      firstSignal.send(1);
      secondSignal.send(2);

      expect(firstReceived.join(',')).assertEqual('1');
      expect(secondReceived.join(',')).assertEqual('2');
    });

    it('uses a stable snapshot when a subscriber is added during send', 0, () => {
      const signal: EventSignal<number> = new EventSignal<number>();
      const cancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const received: string[] = [];
      let added: boolean = false;

      signal.on((value: number) => {
        received.push(`first:${value}`);
        if (!added) {
          added = true;
          signal.on((newValue: number) => {
            received.push(`added:${newValue}`);
          }).into(cancellables);
        }
      }).into(cancellables);

      signal.send(1);
      signal.send(2);

      expect(received.join(',')).assertEqual('first:1,first:2,added:2');
    });

    it('skips a pending subscriber cancelled during send', 0, () => {
      const signal: EventSignal<number> = new EventSignal<number>();
      const cancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const received: string[] = [];
      let pending: EventSignalCancellable | undefined = undefined;

      signal.on((value: number) => {
        received.push(`first:${value}`);
        pending?.cancel();
      }).into(cancellables);
      pending = signal.on((value: number) => {
        received.push(`pending:${value}`);
      });
      pending.into(cancellables);

      signal.send(1);

      expect(received.join(',')).assertEqual('first:1');
    });

    it('isolates a throwing callback from later subscribers', 0, () => {
      const signal: EventSignal<number> = new EventSignal<number>();
      const cancellables: EventSignalCancellableSet = new EventSignalCancellableSet();
      const received: number[] = [];

      signal.on((_value: number) => {
        throw new Error('测试订阅异常隔离');
      }).into(cancellables);
      signal.on((value: number) => received.push(value)).into(cancellables);
      signal.send(9);

      expect(received.join(',')).assertEqual('9');
    });

    it('keeps legacy TermirrorCore listeners compatible with tmEventSignal', 0, () => {
      const received: string[] = [];
      const listener = (event: TmEvent): void => {
        received.push(event.type);
      };

      addEventListener(listener);
      tmEventSignal.send({ sessionId: 1, type: 'output', data: 'first' });
      removeEventListener(listener);
      tmEventSignal.send({ sessionId: 1, type: 'output', data: 'second' });

      expect(received.join(',')).assertEqual('output');
    });
  });
}
