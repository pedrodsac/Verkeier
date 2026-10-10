import MapKit

final class RouteStopAnnotationView: MKAnnotationView {
    static let reuseID = "RouteTraceStop"
    private let circle = UIView()
    private let nameLabel = RouteTraceLabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        clipsToBounds = false
        canShowCallout = false
        isEnabled = false
        displayPriority = .required // Our screen-space layout performs decluttering.
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        nameLabel.numberOfLines = 0
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.isAccessibilityElement = false
        nameLabel.isUserInteractionEnabled = false
        addSubview(nameLabel)
        addSubview(circle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ annotation: RouteStopAnnotation, in mapView: MKMapView) {
        self.annotation = annotation
        let marker = annotation.marker
        isHidden = annotation.placement?.showsCircle != true
        let diameter = RouteTraceStyle.diameter(for: marker.role)
        let color = RouteTraceStyle.color(for: marker.mode)
        circle.frame = CGRect(x: 10 - diameter / 2, y: 10 - diameter / 2, width: diameter, height: diameter)
        circle.layer.cornerRadius = diameter / 2
        circle.backgroundColor = marker.role == .terminus ? color : .systemBackground
        circle.layer.borderColor = (marker.role == .terminus ? UIColor.systemBackground : color)
            .resolvedColor(with: mapView.traitCollection).cgColor
        circle.layer.borderWidth = marker.role == .intermediate ? 2 : 2.5
        alpha = marker.emphasis == .context ? 0.65 : 1
        nameLabel.text = marker.name
        nameLabel.font = RouteTraceStyle.font(in: mapView.traitCollection)
        nameLabel.textColor = .label
        if let labelFrame = annotation.placement?.labelFrame {
            let anchor = mapView.convert(annotation.coordinate, toPointTo: mapView)
            nameLabel.frame = labelFrame.offsetBy(dx: 10 - anchor.x, dy: 10 - anchor.y)
            nameLabel.textAlignment = labelFrame.midX < anchor.x ? .right : .left
            nameLabel.isHidden = false
        } else {
            nameLabel.isHidden = true
        }
        accessibilityLabel = "\(marker.name), \(RouteTraceStyle.roleDescription(marker.role)), \(marker.mode.displayName)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        nameLabel.isHidden = true
        accessibilityLabel = nil
    }
}
