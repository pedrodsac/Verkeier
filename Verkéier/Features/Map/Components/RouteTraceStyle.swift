import SwiftUI
import UIKit

/// Shared visual tokens. Route IDs and names never influence the color.
enum RouteTraceStyle {
    static func color(for mode: TransportMode) -> UIColor {
        switch mode {
        case .walking, .unknown: .secondaryLabel
        default: UIColor(mode.tint)
        }
    }

    static func diameter(for role: RouteMapStopMarker.Role) -> CGFloat {
        switch role {
        case .intermediate: 8
        case .terminus: 16
        default: 12
        }
    }

    static func font(in traits: UITraitCollection, shield: Bool = false) -> UIFont {
        UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: shield ? 10 : 12, weight: shield ? .bold : .semibold),
            compatibleWith: traits)
    }

    static func labelSize(_ text: String, in traits: UITraitCollection) -> CGSize {
        let width = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 110, compatibleWith: traits)
        let font = font(in: traits)
        let rect = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        return CGSize(width: ceil(rect.width) + 4, height: ceil(rect.height) + 4)
    }

    static func shieldSize(_ text: String, in traits: UITraitCollection) -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font(in: traits, shield: true)])
        return CGSize(width: ceil(size.width) + 8, height: ceil(size.height) + 4)
    }

    static func roleDescription(_ role: RouteMapStopMarker.Role) -> String {
        switch role {
        case .intermediate: String(localized: "Intermediate stop")
        case .boarding: String(localized: "Boarding stop")
        case .alighting: String(localized: "Alighting stop")
        case .transfer: String(localized: "Transfer stop")
        case .terminus: String(localized: "Terminus")
        }
    }
}
