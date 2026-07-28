import Testing
@testable import ObservationsMigrationKit

/// These tests exist to make one claim falsifiable: a coalescing state stream
/// and a lossless event stream disagree about how many things happened, and the
/// compiler has nothing to say about it.
@MainActor
@Suite("State coalescing")
struct StateCoalescingTests {

    private func codes(_ count: Int) -> [String] {
        (1...count).map { "SKU-\(String(format: "%04d", $0))" }
    }

    @Test("Twenty synchronous scans produce far fewer than twenty state emissions")
    func synchronousBatchCoalesces() async throws {
        let model = ScannerModel()
        let snapshots = StateStream.snapshots(of: model)

        let consumer = Task {
            var seen: [ScannerSnapshot] = []
            for await snapshot in snapshots {
                seen.append(snapshot)
                if snapshot.scannedCount >= 20 { break }
            }
            return seen
        }

        // Give the consumer a turn to subscribe and take the initial value.
        try await Task.sleep(for: .milliseconds(120))
        model.importBatch(codes(20))

        let seen = await consumer.value

        // Observations emits an initial value on subscription, then one value
        // per transaction — so a 20-scan synchronous batch lands as 2 emissions,
        // not 21. See MeasurementTests for the printed counts.
        #expect(seen.count < 20, "state emissions should be coalesced, not one-per-scan")
        #expect(seen.last?.scannedCount == 20, "final state must still be correct")
    }

    @Test("The final snapshot is correct even though intermediates are gone")
    func finalStateSurvivesCoalescing() async throws {
        let model = ScannerModel()
        let snapshots = StateStream.snapshots(of: model)

        let consumer = Task {
            var last: ScannerSnapshot?
            for await snapshot in snapshots {
                last = snapshot
                if snapshot.scannedCount >= 30 { break }
            }
            return last
        }

        try await Task.sleep(for: .milliseconds(120))
        model.importBatch(codes(10))
        model.importBatch(codes(20))

        let last = await consumer.value

        #expect(last?.scannedCount == 30)
        #expect(last?.isImporting == false, "isImporting flips true and back inside one turn — the stream never sees true")
    }

    @Test("An empty batch changes nothing")
    func emptyBatchIsANoOp() {
        let model = ScannerModel()

        #expect(model.importBatch([]) == 0)
        #expect(model.scannedCount == 0)
        #expect(model.lastCode.isEmpty)
        #expect(model.isImporting == false)
    }

    @Test("Reset returns the model to its initial state")
    func resetClearsState() {
        let model = ScannerModel()
        model.importBatch(codes(5))
        #expect(model.scannedCount == 5)

        model.reset()

        #expect(model.scannedCount == 0)
        #expect(model.lastCode.isEmpty)
        #expect(model.droppedEventCount == 0)
    }
}
