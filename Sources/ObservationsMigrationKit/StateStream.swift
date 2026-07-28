import Observation

/// The state side of the model, as an `AsyncSequence`.
///
/// `Observations` (SE-0475, Swift 6.2 / iOS 26) opens a transaction at the
/// first `willSet` and emits once at the next point of consistency. A synchronous
/// batch of twenty scans therefore arrives as a single coalesced value, not twenty.
///
/// That is the correct behaviour for state and the wrong behaviour for events.
public enum StateStream {

    /// Coalesced, transactional snapshots of the whole model.
    @MainActor
    public static func snapshots(of model: ScannerModel) -> Observations<ScannerSnapshot, Never> {
        Observations { model.snapshot }
    }

    /// Coalesced values for a single property.
    @MainActor
    public static func values<Value: Sendable>(
        of model: ScannerModel,
        at keyPath: KeyPath<ScannerModel, Value> & Sendable
    ) -> Observations<Value, Never> {
        Observations { model[keyPath: keyPath] }
    }
}
