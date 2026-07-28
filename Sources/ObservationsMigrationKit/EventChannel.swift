import Foundation

/// A deliberately boring event channel.
///
/// Nothing here is clever. That is the point. Every lossy decision this type
/// makes is *declared*: the buffer is bounded, the overflow policy is named,
/// and anything it throws away is counted in ``droppedCount``.
///
/// Compare that to a coalescing state stream, which also drops values — but
/// tells nobody, and cannot be asked afterwards how many.
public final class EventChannel<Element: Sendable>: @unchecked Sendable {

    /// What happens when a subscriber is slower than the producer.
    public enum OverflowPolicy: Sendable, Equatable {
        /// Keep the newest events, evict the oldest. Good for "latest activity" UI.
        case dropOldest
        /// Keep the oldest events, reject incoming ones. Good for ordered replay.
        case dropNewest
    }

    /// Maximum events held per subscriber before ``overflowPolicy`` applies.
    public let bufferLimit: Int

    /// The declared behaviour when a subscriber's buffer is full.
    public let overflowPolicy: OverflowPolicy

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var _droppedCount = 0

    public init(bufferLimit: Int = 512, overflowPolicy: OverflowPolicy = .dropOldest) {
        self.bufferLimit = max(1, bufferLimit)
        self.overflowPolicy = overflowPolicy
    }

    /// Number of events that were produced but never delivered — because a
    /// buffer was full, or because nobody was listening.
    public var droppedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _droppedCount
    }

    /// Number of live subscribers.
    public var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    /// A new independent subscription. Each subscriber gets its own buffer.
    public func events() -> AsyncStream<Element> {
        let id = UUID()
        let policy: AsyncStream<Element>.Continuation.BufferingPolicy
        switch overflowPolicy {
        case .dropOldest: policy = .bufferingNewest(bufferLimit)
        case .dropNewest: policy = .bufferingOldest(bufferLimit)
        }

        return AsyncStream(Element.self, bufferingPolicy: policy) { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    /// Deliver one event to every subscriber, counting anything that could not
    /// be delivered.
    public func send(_ element: Element) {
        lock.lock()
        let targets = Array(continuations.values)
        if targets.isEmpty {
            _droppedCount += 1
            lock.unlock()
            return
        }
        lock.unlock()

        var dropped = 0
        for continuation in targets {
            switch continuation.yield(element) {
            case .dropped, .terminated: dropped += 1
            case .enqueued: break
            @unknown default: dropped += 1
            }
        }

        guard dropped > 0 else { return }
        lock.lock()
        _droppedCount += dropped
        lock.unlock()
    }

    /// Finish every subscription.
    public func finish() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets { continuation.finish() }
    }

    /// Reset the dropped-event counter. Useful between demo runs.
    public func resetDroppedCount() {
        lock.lock()
        _droppedCount = 0
        lock.unlock()
    }
}
