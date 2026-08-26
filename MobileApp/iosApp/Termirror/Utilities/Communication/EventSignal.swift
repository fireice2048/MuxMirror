//
//  EventSignal.swift
//  Termirror
//
//  一对多事件监听通信工具
//    注意使用时，Block 不要持有 self（避免内存泄漏）
//    如果监听了全局或单例对象事件的订阅器，将不会析构
//      可以调用 EventSignalCancellable.cancel 取消监听，订阅器也会析构
//    可以使用 EventSignalCancellable.bind(self)，那么当 self 销毁后，订阅器也会析构
//
//  CurrentValueEventSignal 每次有新信号时都会更新到缓存中，可以在建立监听时立即发送信号
//    构造时可传入初始值
//    异步主线程发送
//
//  所有信号都会确保在主线程发送
//
//  Created by medie on 2026/6/19.
//

import Foundation

@objc(XPEventSignal)
open class EventSignal: NSObject, @unchecked Sendable {

    private var subscriberList: [EventSignalSubscriber] = []

    public init(valueType: Any.Type) {
        super.init()
    }

    // 监听事件
    @objc @discardableResult
    public func on(_ callback: @escaping @Sendable (Any) -> Void) -> EventSignalCancellable {
        let subscriber = EventSignalSubscriber()
        subscriber.eventSignal = self
        subscriber.block = callback

        dispatchMainThread {
            self.subscriberList.append(subscriber)
        }

        return subscriber
    }

    // 发送事件（value）
    @objc public func send(_ value: Any) {
        _send(value)
    }

    // 内部使用（发送 nil）
    func _send(_ value: Any?) {
        // value 只跨线程传递到主线程读取一次，由本类保证串行化
        nonisolated(unsafe) let value = value
        dispatchMainThread {
            let list = Array(self.subscriberList)
            list.forEach { subscriber in
                subscriber.send(value: value)
            }
        }
    }

    // 移除监听
    func remove(_ subscriber: EventSignalCancellable) {
        guard let subscriber = subscriber as? EventSignalSubscriber else { return }
        dispatchMainThread {
            if let index = self.subscriberList.firstIndex(of: subscriber) {
                self.subscriberList.remove(at: index)
            }
        }
    }
}

@objc(XPNullableEventSignal)
open class NullableEventSignal: EventSignal {

    public override init(valueType: Any.Type) {
        super.init(valueType: valueType)
    }

    public init() {
        super.init(valueType: Any.self)
    }

    // 发送事件（value）
    @objc public override func send(_ value: Any?) {
        super._send(value)
    }
}

// 建立监听时可立即收到信号（异步主线程回调）
@objc(XPCurrentValueEventSignal)
open class CurrentValueEventSignal: NullableEventSignal, @unchecked Sendable {

    private var cachedValue: Any?

    public init(valueType: Any.Type, cachedValue: Any? = nil) {
        self.cachedValue = cachedValue
        super.init(valueType: valueType)
    }

    @objc public func onImmediately(
        _ callback: @escaping @Sendable (Any?) -> Void
    ) -> EventSignalCancellable {
        let cancellable = super.on(callback)
        DispatchQueue.main.async {
            callback(self.cachedValue)
        }

        return cancellable
    }

    @objc public override func on(
        _ callback: @escaping @Sendable (Any) -> Void
    ) -> EventSignalCancellable {
        super.on(callback)
    }

    /// 发送事件（value）
    @objc public override func send(_ value: Any?) {
        // cachedValue 的写入确保在主线程，与 onImmediately 的读取串行化，避免数据竞争
        nonisolated(unsafe) let value = value
        dispatchMainThread {
            self.cachedValue = value
        }
        super.send(value)
    }

    /// 重置缓存（不发信号）
    @objc public func resetCache(cachedValue: Any? = nil) {
        nonisolated(unsafe) let newValue = cachedValue
        dispatchMainThread {
            self.cachedValue = newValue
        }
    }
}

@objc(XPEventSignalCancellable)
public protocol EventSignalCancellable {
    func cancel()
    func bind(_ target: AnyObject)
    func into(_ cancellableSet: EventSignalCancellableSet)
}

class EventSignalSubscriber: NSObject, EventSignalCancellable, @unchecked Sendable {
    weak var eventSignal: EventSignal?
    weak var bindTarget: AnyObject? = EventSignalSubscriber.self

    var block: ((Any?) -> Void)?

    deinit {
        print("EventSignalSubscriber deinit 订阅器析构")
    }

    override init() {
        super.init()
        print("EventSignalSubscriber init 订阅器构造")
    }

    public func cancel() {
        eventSignal?.remove(self)
        block = nil
    }

    func bind(_ target: AnyObject) {
        bindTarget = target
    }

    func into(_ cancellableSet: EventSignalCancellableSet) {
        cancellableSet.append(cancellable: self)
    }

    func send(value: Any?) {
        guard bindTarget != nil else {
            print("EventSignalSubscriber 检测到目标已销毁，取消订阅器")
            cancel()
            return
        }

        block?(value)
    }
}

@objc(XPEventSignalCancellableSet)
open class EventSignalCancellableSet: NSObject {
    private var cancellableSet: [EventSignalCancellable] = []
    private let lock = NSLock()

    public func append(cancellable: EventSignalCancellable) {
        lock.lock()
        cancellableSet.append(cancellable)
        lock.unlock()
    }

    public func cancelAll() {
        lock.lock()
        let list = Array(cancellableSet)
        cancellableSet = []
        lock.unlock()
        list.forEach { cancellable in
            cancellable.cancel()
        }
    }
}

func dispatchMainThread(block: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.async {
            block()
        }
    }
}
