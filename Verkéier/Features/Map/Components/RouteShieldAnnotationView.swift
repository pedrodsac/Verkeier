import MapKit

final class RouteShieldAnnotationView: MKAnnotationView {
    static let reuseID = "RouteTraceShield"
    private let label = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isEnabled = false
        canShowCallout = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        displayPriority = .required
        layer.cornerRadius = 3
        label.textAlignment = .center
        label.textColor = .white
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ annotation: RouteShieldAnnotation, traits: UITraitCollection) {
        self.annotation = annotation
        let segment = annotation.segment
        let text = segment.routeShortName ?? ""
        let size = RouteTraceStyle.shieldSize(text, in: traits)
        bounds = CGRect(origin: .zero, size: size)
        label.frame = bounds
        label.font = RouteTraceStyle.font(in: traits, shield: true)
        label.text = text
        backgroundColor = RouteTraceStyle.color(for: segment.mode)
        alpha = segment.emphasis == .context ? 0.55 : 1
        isHidden = !annotation.isPlaced
    }
}
