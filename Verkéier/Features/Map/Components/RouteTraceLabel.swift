import UIKit

/// Map-style text halo without mutating label properties during drawing.
final class RouteTraceLabel: UILabel {
    override func drawText(in rect: CGRect) {
        guard let text, let font else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineBreakMode = .byWordWrapping
        let foreground = (textColor ?? .label).resolvedColor(with: traitCollection)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: foreground,
            .strokeColor: UIColor.systemBackground.resolvedColor(with: traitCollection),
            .strokeWidth: 18, .paragraphStyle: paragraph
        ]
        let textRect = rect.insetBy(dx: 2, dy: 2)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        // Draw the halo first, then the primary-colored glyphs. A combined
        // fill-and-stroke pass lets the thick halo cover the letter interiors.
        NSAttributedString(string: text, attributes: attributes).draw(with: textRect, options: options, context: nil)
        attributes[.strokeWidth] = 0
        NSAttributedString(string: text, attributes: attributes).draw(with: textRect, options: options, context: nil)
    }
}
