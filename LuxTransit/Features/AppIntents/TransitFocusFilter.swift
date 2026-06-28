import AppIntents
import Foundation

/// Shared flag for whether a work-focused filter is currently active, written by
/// the Focus filter intent and read by the favourites UI.
nonisolated struct FocusFilterStore {
    nonisolated(unsafe) static let shared = FocusFilterStore(
        defaults: UserDefaults(suiteName: SharedTransitDataStore.appGroupIdentifier) ?? .standard
    )

    let defaults: UserDefaults
    private let key = "FocusFilter.workActive"

    var isWorkFocusActive: Bool {
        get { defaults.bool(forKey: key) }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}

/// A Focus filter (Settings → Focus → Add Filter) that narrows the app to
/// work-relevant stops while a Focus such as Work is on.
struct TransitFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Work stops only"
    static let description = IntentDescription(
        "Show only stops labelled “Work” and your commute preset while this Focus is on."
    )

    @Parameter(title: "Work stops only", default: true)
    var workOnly: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: workOnly ? "Work stops only" : "All stops")
    }

    func perform() async throws -> some IntentResult {
        FocusFilterStore.shared.isWorkFocusActive = workOnly
        return .result()
    }
}
