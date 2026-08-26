import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0xD004;
const LOG_TAG: string = 'EventSignal';

/**
 * EventSignal 的订阅回调。
 *
 * 回调在 send 所在线程同步执行，不应执行耗时或阻塞操作。
 */
export type EventSignalCallback<T> = (value: T) => void;

/**
 * 单个 EventSignal 订阅的生命周期令牌。
 */
export interface EventSignalCancellable {
  readonly isCancelled: boolean;

  /**
   * 取消订阅。可以安全地重复调用。
   */
  cancel(): void;

  /**
   * 将订阅令牌保存到集合中。
   */
  into(cancellableSet: EventSignalCancellableSet): void;
}

/**
 * 强引用保存多个订阅令牌，并支持统一取消。
 */
export class EventSignalCancellableSet {
  private cancellables: Set<EventSignalCancellable> = new Set<EventSignalCancellable>();

  get count(): number {
    return this.cancellables.size;
  }

  insert(cancellable: EventSignalCancellable): void {
    if (!cancellable.isCancelled) {
      this.cancellables.add(cancellable);
    }
  }

  /**
   * 取消并移除集合中的全部订阅。
   */
  cancelAll(): void {
    const cancellables: EventSignalCancellable[] = Array.from(this.cancellables);
    this.cancellables.clear();
    cancellables.forEach((cancellable: EventSignalCancellable) => {
      cancellable.cancel();
    });
  }

  /**
   * 移除已经单独取消的令牌，适用于长期复用的集合。
   */
  removeCancelled(): void {
    this.cancellables.forEach((cancellable: EventSignalCancellable) => {
      if (cancellable.isCancelled) {
        this.cancellables.delete(cancellable);
      }
    });
  }
}

class EventSignalSubscriber<T> implements EventSignalCancellable {
  private registry?: WeakRef<EventSignalRegistry<T>>;
  private callback?: EventSignalCallback<T>;
  private cancelled: boolean = false;
  private readonly identifier: number;

  constructor(
    registry: EventSignalRegistry<T>,
    identifier: number,
    callback: EventSignalCallback<T>
  ) {
    this.registry = new WeakRef<EventSignalRegistry<T>>(registry);
    this.identifier = identifier;
    this.callback = callback;
  }

  get isCancelled(): boolean {
    return this.cancelled;
  }

  cancel(): void {
    if (this.cancelled) {
      return;
    }

    this.cancelled = true;
    this.callback = undefined;
    this.registry?.deref()?.remove(this.identifier);
    this.registry = undefined;
  }

  into(cancellableSet: EventSignalCancellableSet): void {
    cancellableSet.insert(this);
  }

  notify(value: T): void {
    if (this.cancelled || this.callback === undefined) {
      return;
    }

    try {
      this.callback(value);
    } catch (error) {
      hilog.error(
        LOG_DOMAIN,
        LOG_TAG,
        '订阅回调执行失败: %{public}s',
        JSON.stringify(error)
      );
    }
  }
}

class EventSignalRegistry<T> {
  private subscribers: Map<number, WeakRef<EventSignalSubscriber<T>>> =
    new Map<number, WeakRef<EventSignalSubscriber<T>>>();
  private nextIdentifier: number = 1;

  subscribe(callback: EventSignalCallback<T>): EventSignalSubscriber<T> {
    const identifier: number = this.nextIdentifier;
    this.nextIdentifier += 1;

    const subscriber: EventSignalSubscriber<T> =
      new EventSignalSubscriber<T>(this, identifier, callback);
    this.subscribers.set(
      identifier,
      new WeakRef<EventSignalSubscriber<T>>(subscriber)
    );
    return subscriber;
  }

  remove(identifier: number): void {
    this.subscribers.delete(identifier);
  }

  send(value: T): void {
    const snapshot: WeakRef<EventSignalSubscriber<T>>[] =
      Array.from(this.subscribers.values());

    snapshot.forEach((subscriberReference: WeakRef<EventSignalSubscriber<T>>) => {
      const subscriber: EventSignalSubscriber<T> | undefined = subscriberReference.deref();
      if (subscriber === undefined) {
        this.removeReference(subscriberReference);
        return;
      }
      subscriber.notify(value);
    });
  }

  count(): number {
    this.pruneReleasedSubscribers();
    return this.subscribers.size;
  }

  private pruneReleasedSubscribers(): void {
    const releasedIdentifiers: number[] = [];
    this.subscribers.forEach((
      subscriberReference: WeakRef<EventSignalSubscriber<T>>,
      identifier: number
    ) => {
      if (subscriberReference.deref() === undefined) {
        releasedIdentifiers.push(identifier);
      }
    });
    releasedIdentifiers.forEach((identifier: number) => {
      this.subscribers.delete(identifier);
    });
  }

  private removeReference(
    targetReference: WeakRef<EventSignalSubscriber<T>>
  ): void {
    let targetIdentifier: number | undefined = undefined;
    this.subscribers.forEach((
      subscriberReference: WeakRef<EventSignalSubscriber<T>>,
      identifier: number
    ) => {
      if (subscriberReference === targetReference) {
        targetIdentifier = identifier;
      }
    });
    if (targetIdentifier !== undefined) {
      this.subscribers.delete(targetIdentifier);
    }
  }
}

/**
 * 同一 ArkTS 线程内、类型安全的一对多事件信号。
 *
 * Signal 仅弱持有订阅者。调用方必须持有返回的订阅令牌，通常使用
 * EventSignalCancellableSet 统一保存。
 *
 * 跨 TaskPool 或 Worker 的通信应使用 HarmonyOS Emitter。
 */
export class EventSignal<T> {
  private readonly registry: EventSignalRegistry<T> = new EventSignalRegistry<T>();

  get subscriberCount(): number {
    return this.registry.count();
  }

  on(callback: EventSignalCallback<T>): EventSignalCancellable {
    return this.registry.subscribe(callback);
  }

  send(value: T): void {
    this.registry.send(value);
  }
}

/**
 * 保存最新值的 EventSignal。
 *
 * 新订阅者建立订阅时，会在当前线程同步收到最新值。
 */
export class CurrentValueEventSignal<T> extends EventSignal<T> {
  private currentValue: T;

  constructor(initialValue: T) {
    super();
    this.currentValue = initialValue;
  }

  get value(): T {
    return this.currentValue;
  }

  on(callback: EventSignalCallback<T>): EventSignalCancellable {
    const cancellable: EventSignalCancellable = super.on(callback);
    try {
      callback(this.currentValue);
    } catch (error) {
      hilog.error(
        LOG_DOMAIN,
        LOG_TAG,
        '当前值订阅回调执行失败: %{public}s',
        JSON.stringify(error)
      );
    }
    return cancellable;
  }

  send(value: T): void {
    this.currentValue = value;
    super.send(value);
  }

  /**
   * 只替换当前值，不向现有订阅者发送事件。
   */
  resetCurrentValue(value: T): void {
    this.currentValue = value;
  }
}
