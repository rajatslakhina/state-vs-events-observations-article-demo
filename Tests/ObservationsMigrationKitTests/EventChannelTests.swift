import Testing
@testable import ObservationsMigrationKit

@MainActor
@Suite("Event delivery")
struct EventChannelTests {

    private func codes(_ count: Int) -> [String] {
        (1...count).map { "SKU-\(String(format: "%04d", $0))" }
    }

    @Test("Every scan in a synchronous batch arrives as its own event, in order")
    func batchDeliversEveryEvent() async throws {
        let model = ScannerModel()
        let events = model.scanEvents()

        let consumer = Task {
            var received: [ScanEvent] = []
            for await event in events {
                received.append(event)
                if received.count == 20 { break }
            }
            return received
        }

        try await Task.sleep(for: .milliseconds(120))
        model.importBatch(codes(20))

        let received = await consumer.value

        #expect(received.count == 20)
        #expect(received.map(\.sequence) == Array(1...20))
        #expect(received.first?.code == "SKU-0001")
        #expect(received.last?.code == "SKU-0020")
        #expect(model.droppedEventCount == 0)
    }

    @Test("Two subscribers each receive the full batch")
    func multipleSubscribersEachGetEverything() async throws {
        let model = ScannerModel()
        let first = model.scanEvents()
        let second = model.scanEvents()

        let a = Task { var n = 0; for await _ in first { n += 1; if n == 8 { break } }; return n }
        let b = Task { var n = 0; for await _ in second { n += 1; if n == 8 { break } }; return n }

        try await Task.sleep(for: .milliseconds(120))
        model.importBatch(codes(8))

        #expect(await a.value == 8)
        #expect(await b.value == 8)
    }

    @Test("Overflowing a bounded buffer is counted, not silent")
    func overflowIsCountedAndKeepsNewest() async throws {
        let model = ScannerModel(bufferLimit: 8, overflowPolicy: .dropOldest)
        let events = model.scanEvents()

        // Nobody drains the stream while the batch runs, so the buffer overflows.
        model.importBatch(codes(40))

        #expect(model.droppedEventCount == 32, "40 produced, 8 retained")

        var received: [ScanEvent] = []
        for await event in events {
            received.append(event)
            if received.count == 8 { break }
        }

        #expect(received.map(\.sequence) == Array(33...40), "dropOldest keeps the newest window")
    }

    @Test("dropNewest keeps the oldest window instead")
    func dropNewestKeepsOldest() async throws {
        let model = ScannerModel(bufferLimit: 5, overflowPolicy: .dropNewest)
        let events = model.scanEvents()

        model.importBatch(codes(12))

        #expect(model.droppedEventCount == 7)

        var received: [ScanEvent] = []
        for await event in events {
            received.append(event)
            if received.count == 5 { break }
        }

        #expect(received.map(\.sequence) == Array(1...5))
    }

    @Test("Events sent with no subscriber are counted as dropped, not swallowed")
    func noSubscriberStillCounts() {
        let model = ScannerModel()

        model.importBatch(codes(6))

        #expect(model.scannedCount == 6, "state still advances")
        #expect(model.droppedEventCount == 6, "but six events had nowhere to go, and we know it")
    }

    @Test("A channel with a zero or negative buffer limit is clamped, not crashed")
    func bufferLimitIsClamped() {
        #expect(EventChannel<ScanEvent>(bufferLimit: 0).bufferLimit == 1)
        #expect(EventChannel<ScanEvent>(bufferLimit: -17).bufferLimit == 1)
    }

    @Test("Finishing the channel ends iteration and clears subscribers")
    func finishEndsIteration() async throws {
        let channel = EventChannel<ScanEvent>()
        let stream = channel.events()

        let consumer = Task {
            var n = 0
            for await _ in stream { n += 1 }
            return n
        }

        try await Task.sleep(for: .milliseconds(80))
        channel.send(ScanEvent(sequence: 1, code: "SKU-0001"))
        channel.send(ScanEvent(sequence: 2, code: "SKU-0002"))
        channel.finish()

        #expect(await consumer.value == 2)
        #expect(channel.subscriberCount == 0)
    }
}
