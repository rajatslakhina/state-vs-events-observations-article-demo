import Foundation
import Observation

/// One scan. An *event*: it happened once, at a point in time, and no later
/// value can reconstruct it.
public struct ScanEvent: Sendable, Equatable, Identifiable {
    public let sequence: Int
    public let code: String

    public var id: Int { sequence }

    public init(sequence: Int, code: String) {
        self.sequence = sequence
        self.code = code
    }
}

/// A consistent view of the model. *State*: if you lost it, you could recompute
/// it from the model as it is right now.
public struct ScannerSnapshot: Sendable, Equatable {
    public let scannedCount: Int
    public let lastCode: String
    public let isImporting: Bool

    public init(scannedCount: Int, lastCode: String, isImporting: Bool) {
        self.scannedCount = scannedCount
        self.lastCode = lastCode
        self.isImporting = isImporting
    }
}

/// A warehouse scanner model that carries both kinds of change at once — which
/// is exactly the situation Combine used to paper over.
///
/// `scannedCount` / `lastCode` are state. Every individual scan is an event.
/// The two need different transports, and this type gives them different
/// transports on purpose.
@MainActor
@Observable
public final class ScannerModel {

    public private(set) var scannedCount: Int = 0
    public private(set) var lastCode: String = ""
    public private(set) var isImporting: Bool = false

    @ObservationIgnored private let channel: EventChannel<ScanEvent>

    public init(bufferLimit: Int = 512, overflowPolicy: EventChannel<ScanEvent>.OverflowPolicy = .dropOldest) {
        self.channel = EventChannel(bufferLimit: bufferLimit, overflowPolicy: overflowPolicy)
    }

    /// The current consistent state, as one value.
    public var snapshot: ScannerSnapshot {
        ScannerSnapshot(scannedCount: scannedCount, lastCode: lastCode, isImporting: isImporting)
    }

    /// The lossless event side. Each subscriber gets every scan, in order.
    public func scanEvents() -> AsyncStream<ScanEvent> {
        channel.events()
    }

    /// Events produced but not delivered. Should be 0 in the demo's happy path.
    public var droppedEventCount: Int { channel.droppedCount }

    /// A batch arriving in a single synchronous turn: a bulk import, a queue
    /// replayed after reconnect, or a barcode gun firing faster than the run
    /// loop can breathe.
    ///
    /// - Returns: the number of scans recorded.
    @discardableResult
    public func importBatch(_ codes: [String]) -> Int {
        guard !codes.isEmpty else { return 0 }

        isImporting = true
        for code in codes {
            scannedCount += 1
            lastCode = code
            channel.send(ScanEvent(sequence: scannedCount, code: code))
        }
        isImporting = false

        return codes.count
    }

    /// A single scan. Same path as a batch of one, deliberately.
    public func scanOne(_ code: String) {
        importBatch([code])
    }

    /// Reset counters. Events already delivered stay delivered — that is what
    /// makes them events.
    public func reset() {
        scannedCount = 0
        lastCode = ""
        isImporting = false
        channel.resetDroppedCount()
    }
}
