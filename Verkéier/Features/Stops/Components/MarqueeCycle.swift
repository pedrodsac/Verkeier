import QuartzCore

/// Presentation timing only. Movement is always leftward; repeating the
/// keyframes resets instantly rather than interpolating back to the start.
struct MarqueeCycle: Equatable {
    static let readingPause: Double = 1.5
    static let pointsPerSecond: Double = 35
    static let overflowTolerance: CGFloat = 1

    let startOffset: CGFloat
    let endOffset: CGFloat
    let startPause: Double
    let endPause: Double

    init(distance: CGFloat) {
        startOffset = 0
        endOffset = -max(0, distance)
        startPause = Self.readingPause
        endPause = Self.readingPause
    }

    private init(startOffset: CGFloat, endOffset: CGFloat, startPause: Double, endPause: Double) {
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.startPause = startPause
        self.endPause = endPause
    }

    static func distance(contentWidth: CGFloat, viewportWidth: CGFloat, leadingInset: CGFloat) -> CGFloat {
        guard contentWidth > 0, viewportWidth > 0 else { return 0 }
        let overflow = contentWidth + leadingInset - viewportWidth
        return overflow > overflowTolerance ? overflow : 0
    }

    var movementDuration: Double { Double(startOffset - endOffset) / Self.pointsPerSecond }
    var duration: Double { startPause + movementDuration + endPause }

    func offset(at elapsed: Double) -> CGFloat {
        let travel = min(movementDuration, max(0, elapsed - startPause))
        return startOffset - CGFloat(travel * Self.pointsPerSecond)
    }

    /// Continue the current cycle after a resize without reversing or snapping.
    /// If the viewport grew, hold the current position until the normal reset.
    func remainder(at elapsed: Double, distance: CGFloat, displayedOffset: CGFloat? = nil) -> Self {
        let current = displayedOffset ?? offset(at: elapsed)
        let end = min(current, -distance)
        let remainingEndPause = max(0.001, duration - elapsed)
        return Self(
            startOffset: current,
            endOffset: end,
            startPause: max(0, startPause - elapsed),
            endPause: elapsed >= startPause + movementDuration && end == current
                ? remainingEndPause : Self.readingPause
        )
    }

    func animation(repeats: Bool) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [startOffset, startOffset, endOffset, endOffset]
        animation.keyTimes = [0, NSNumber(value: startPause / duration),
                             NSNumber(value: (startPause + movementDuration) / duration), 1]
        animation.duration = duration
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .linear), count: 3)
        animation.repeatCount = repeats ? .infinity : 0
        return animation
    }
}
