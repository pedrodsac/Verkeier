import SwiftUI
import UIKit

/// Presentation instrumentation only. A second display callback follows a
/// committed frame containing the complete result and the idle loading state.
struct RouteRenderObserver: UIViewRepresentable {
    let requestID: UUID
    let rendered: (UUID) -> Void
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.observe(requestID, rendered: rendered)
    }
    static func dismantleUIView(_ view: ObserverView, coordinator: Void) { view.stop() }

    final class ObserverView: UIView {
        private var requestID: UUID?
        private var displayLink: CADisplayLink?
        private var frames = 0
        private var rendered: ((UUID) -> Void)?
        func observe(_ id: UUID, rendered: @escaping (UUID) -> Void) {
            guard requestID != id else { return }
            stop(); requestID = id; self.rendered = rendered; frames = 0
            let link = CADisplayLink(target: self, selector: #selector(displayFrame))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }
        @objc private func displayFrame() {
            guard window != nil, let requestID else { return }
            frames += 1
            guard frames >= 2 else { return }
            let callback = rendered
            stop()
            callback?(requestID)
        }
        func stop() { displayLink?.invalidate(); displayLink = nil; rendered = nil }
    }
}
