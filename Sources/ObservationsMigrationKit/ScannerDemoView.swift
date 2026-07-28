#if canImport(SwiftUI)
import SwiftUI

/// The whole argument on one screen.
///
/// Tap "Import batch of 20" and watch the two counters disagree: the state
/// stream ticks once, the event stream ticks twenty times. Same batch, same
/// model, same run loop turn.
@available(iOS 26.0, macOS 26.0, *)
public struct ScannerDemoView: View {

    @State private var model = ScannerModel()
    @State private var stateEmissions = 0
    @State private var eventsDelivered = 0
    @State private var lastCode = "—"
    @State private var batchSize = 20

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    HStack(spacing: 14) {
                        counterCard(
                            title: "State emissions",
                            value: stateEmissions,
                            caption: "Observations — coalesced",
                            tint: .blue
                        )
                        counterCard(
                            title: "Events delivered",
                            value: eventsDelivered,
                            caption: "AsyncStream — lossless",
                            tint: .green
                        )
                    }

                    factsPanel
                    controls
                    footnote
                }
                .padding(20)
            }
            .navigationTitle("State vs. Events")
        }
        .task {
            for await snapshot in StateStream.snapshots(of: model) {
                stateEmissions += 1
                lastCode = snapshot.lastCode.isEmpty ? "—" : snapshot.lastCode
            }
        }
        .task {
            for await _ in model.scanEvents() {
                eventsDelivered += 1
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One batch. Two truths.")
                .font(.title2.bold())
            Text("A batch of scans mutates the model \(batchSize) times in a single synchronous turn. Watch what each stream reports.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func counterCard(title: String, value: Int, caption: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("\(value)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var factsPanel: some View {
        VStack(spacing: 10) {
            row("Scans recorded (state)", "\(model.scannedCount)")
            Divider()
            row("Last code", lastCode)
            Divider()
            row("Events dropped", "\(model.droppedEventCount)")
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospaced().weight(.semibold))
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                model.importBatch(batch())
            } label: {
                Label("Import batch of \(batchSize)", systemImage: "shippingbox.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 12) {
                Button {
                    model.scanOne("SKU-\(String(format: "%04d", model.scannedCount + 1))")
                } label: {
                    Label("Scan one", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    model.reset()
                    stateEmissions = 0
                    eventsDelivered = 0
                    lastCode = "—"
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    private var footnote: some View {
        Text("The state stream is not broken. It is doing its job: reporting the latest consistent value. It just cannot tell you that \(batchSize) things happened.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func batch() -> [String] {
        let start = model.scannedCount + 1
        guard batchSize > 0 else { return [] }
        return (start..<(start + batchSize)).map { "SKU-\(String(format: "%04d", $0))" }
    }
}

@available(iOS 26.0, macOS 26.0, *)
#Preview {
    ScannerDemoView()
}
#endif
