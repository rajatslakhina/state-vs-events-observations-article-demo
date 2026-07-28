import Testing
@testable import ObservationsMigrationKit

/// The number quoted in the article, as an executable measurement.
///
/// Run `swift test` and this prints the two counts side by side. On Swift 6.2
/// it reports 2 state emissions against 20 delivered events, every time.
@MainActor
@Suite("Measurement")
struct MeasurementTests {

    @Test("A 20-scan batch: state emissions vs. events delivered")
    func measureBatchOfTwenty() async throws {
        let batch = (1...20).map { "SKU-\(String(format: "%04d", $0))" }

        let model = ScannerModel()
        let snapshots = StateStream.snapshots(of: model)
        let events = model.scanEvents()

        let stateConsumer = Task {
            var count = 0
            for await snapshot in snapshots {
                count += 1
                if snapshot.scannedCount >= batch.count { break }
            }
            return count
        }

        let eventConsumer = Task {
            var count = 0
            for await _ in events {
                count += 1
                if count == batch.count { break }
            }
            return count
        }

        // Let both consumers subscribe before the batch runs.
        try await Task.sleep(for: .milliseconds(150))
        model.importBatch(batch)

        let stateEmissions = await stateConsumer.value
        let eventsDelivered = await eventConsumer.value

        print("""
        MEASURED — scans: \(batch.count) \
        · state emissions: \(stateEmissions) \
        · events delivered: \(eventsDelivered) \
        · events dropped: \(model.droppedEventCount)
        """)

        #expect(eventsDelivered == batch.count)
        #expect(model.droppedEventCount == 0)
        #expect(stateEmissions < batch.count)
        // The initial value plus one coalesced transaction for the whole batch.
        #expect(stateEmissions <= 3)
    }
}
