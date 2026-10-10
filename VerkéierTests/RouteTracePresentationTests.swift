import MapKit
import SwiftUI
import Testing
@testable import Verkeier

@MainActor
struct RouteTracePresentationTests {
    @Test func customRendererInitializesAndDrawsEveryTraceStyle() {
        let coordinates = [CLLocationCoordinate2D(latitude: 49.6, longitude: 6.1),
                           CLLocationCoordinate2D(latitude: 49.61, longitude: 6.11)]
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        for mode in TransportMode.allCases {
            let segment = RouteMapSegment(id: "test", mode: mode, coordinates: [], emphasis: .highlighted)
            let renderer = RouteTraceRenderer(polyline: polyline, segment: segment,
                traits: UITraitCollection(userInterfaceStyle: .light))
            #expect(renderer.polyline === polyline)
            #expect(renderer.path != nil)
            // No map or network is needed to exercise MapKit's renderer setup.
            let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { output in
                renderer.draw(polyline.boundingMapRect, zoomScale: 1, in: output.cgContext)
            }
            #expect(image.size == CGSize(width: 32, height: 32))
        }
    }

    @Test(arguments: [TransportMode.bus, .train, .tram, .funicular, .bicycle])
    func traceUsesCanonicalModeColor(_ mode: TransportMode) {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        #expect(RouteTraceStyle.color(for: mode).resolvedColor(with: traits)
            == UIColor(mode.tint).resolvedColor(with: traits))
    }

    @Test func walkingAndUnknownAreNeutralAndSupportDarkMode() {
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            #expect(RouteTraceStyle.color(for: .walking).resolvedColor(with: traits) == UIColor.secondaryLabel.resolvedColor(with: traits))
            #expect(RouteTraceStyle.color(for: .unknown).resolvedColor(with: traits) == UIColor.secondaryLabel.resolvedColor(with: traits))
        }
    }

    @Test func stopAnnotationRetainsIdentityAndOnlyNotifiesOnChangedCoordinates() {
        let annotation = RouteStopAnnotation(marker: marker())
        var changes = 0
        let observation = annotation.observe(\.coordinate) { _, _ in changes += 1 }
        annotation.update(marker(name: "Renamed"))
        #expect(changes == 0)
        annotation.update(marker(name: "Renamed", latitude: 49.7))
        annotation.update(marker(name: "Renamed", latitude: 49.7))
        #expect(changes == 1)
        #expect(annotation.marker.id == "visit")
        #expect(annotation.title == "Renamed")
        observation.invalidate()
    }

    @Test func dynamicTypeGrowsLabelsAndShields() {
        let normal = UITraitCollection(preferredContentSizeCategory: .large)
        let large = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        #expect(RouteTraceStyle.labelSize("Gromscheed", in: large).height > RouteTraceStyle.labelSize("Gromscheed", in: normal).height)
        #expect(RouteTraceStyle.shieldSize("322", in: large).width > RouteTraceStyle.shieldSize("322", in: normal).width)
        let longName = "Kirchberg, Gare routière Luxexpo, a long stop name that needs several lines of text"
        #expect(RouteTraceStyle.labelSize(longName, in: normal).height > RouteTraceStyle.font(in: normal).lineHeight * 2)
    }

    @Test func labelHaloLeavesPrimaryTextVisibleInBothAppearances() throws {
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let label = RouteTraceLabel(frame: CGRect(x: 0, y: 0, width: 150, height: 60))
            label.overrideUserInterfaceStyle = appearance
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .label
            label.text = "Gromscheed"
            let format = UIGraphicsImageRendererFormat()
            format.preferredRange = .standard
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: label.bounds.size, format: format).image { output in
                (appearance == .light ? UIColor.white : UIColor.black).setFill()
                output.fill(label.bounds)
                label.drawText(in: label.bounds)
            }
            let pixels = try #require(image.cgImage?.dataProvider?.data)
            let bytes = try #require(CFDataGetBytePtr(pixels))
            let foregroundPixels = stride(from: 0, to: CFDataGetLength(pixels) - 3, by: 4).filter { offset in
                let channels = [bytes[offset], bytes[offset + 1], bytes[offset + 2]]
                return appearance == .light ? channels.allSatisfy { $0 < 80 } : channels.allSatisfy { $0 > 175 }
            }
            #expect(foregroundPixels.count > 10)
        }
    }

    @Test func routeDecorationsIntroduceNoTapActions() {
        let stop = RouteStopAnnotationView(annotation: RouteStopAnnotation(marker: marker()), reuseIdentifier: "test")
        let shield = RouteShieldAnnotationView(annotation: nil, reuseIdentifier: "test")
        #expect(!stop.isEnabled && !stop.canShowCallout)
        #expect(stop.isAccessibilityElement)
        #expect(stop.accessibilityTraits.contains(.staticText))
        #expect(!shield.isEnabled && shield.accessibilityElementsHidden)
    }

    private func marker(name: String = "Gromscheed", latitude: Double = 49.65) -> RouteMapStopMarker {
        .init(id: "visit", name: name, coordinate: .init(latitude: latitude, longitude: 6.2),
            segmentIDs: ["bus"], mode: .bus, role: .boarding)
    }
}
