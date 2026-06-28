import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes favourite stops into the on-device CoreSpotlight index so riders can
/// search a saved stop from iOS Spotlight and deep-link straight to its detail.
///
/// Items use the `stop.<id>` unique identifier and a shared domain identifier so
/// the whole set can be cleared in one call when the last favourite is removed.
enum FavouriteStopSpotlightIndexer {
    static let domainIdentifier = "lu.luxtransit.favouritestop"

    static func index(_ stops: [Stop]) {
        let items = stops.map { stop -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .item)
            attrs.title = stop.name
            attrs.contentDescription = [
                stop.locality,
                stop.modes.map(\.displayName).joined(separator: ", ")
            ]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            attrs.keywords = [stop.name, stop.locality].compactMap(\.self)
            return CSSearchableItem(
                uniqueIdentifier: "stop.\(stop.id)",
                domainIdentifier: domainIdentifier,
                attributeSet: attrs
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainIdentifier]
        ) { _ in }
    }
}
