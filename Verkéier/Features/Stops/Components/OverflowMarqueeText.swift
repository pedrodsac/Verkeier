import SwiftUI
import UIKit

/// A single, readable destination. Core Animation owns its movement, so board
/// refreshes and countdown updates cannot interpolate or restart the marquee.
struct OverflowMarqueeText: View {
    let text: String
    let font: Font
    var initialLeadingInset: CGFloat = 0
    var forceScroll = false
    var foregroundColor: Color = .primary

    @Environment(\.fontResolutionContext) private var fontContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        MarqueeLabelRepresentable(
            text: text,
            font: font.resolve(in: fontContext).ctFont as UIFont,
            color: UIColor(foregroundColor),
            leadingInset: initialLeadingInset,
            forceScroll: forceScroll,
            reduceMotion: reduceMotion,
            isActive: isVisible && scenePhase == .active
        )
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

private struct MarqueeLabelRepresentable: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor
    let leadingInset: CGFloat
    let forceScroll: Bool
    let reduceMotion: Bool
    let isActive: Bool

    func makeUIView(context: Context) -> MarqueeLabelView { MarqueeLabelView() }

    func updateUIView(_ view: MarqueeLabelView, context: Context) {
        view.configure(text: text, font: font, color: color, leadingInset: leadingInset,
                       forceScroll: forceScroll, reduceMotion: reduceMotion, isActive: isActive)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarqueeLabelView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
               height: max(proposal.height ?? 0, uiView.intrinsicContentSize.height))
    }

    static func dismantleUIView(_ view: MarqueeLabelView, coordinator: Void) { view.stop() }
}

final class MarqueeLabelView: UIView, CAAnimationDelegate {
    static let animationKey = "destination.scroll"
    private let label = UILabel()
    private let clock: () -> CFTimeInterval
    private var leadingInset: CGFloat = 0
    private var reduceMotion = false
    private var isActive = false
    private var viewportWidth: CGFloat = 0
    private var cycleStart: CFTimeInterval = 0
    private var repeats = true
    private(set) var cycle: MarqueeCycle?
    private(set) var animationGeneration = 0

    init(clock: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.clock = clock
        super.init(frame: .zero)
        clipsToBounds = true
        isAccessibilityElement = false
        label.isAccessibilityElement = false
        label.numberOfLines = 1
        label.textAlignment = .left
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        let size = label.intrinsicContentSize
        return CGSize(width: max(0, size.width + leadingInset), height: max(20, size.height))
    }

    func configure(text: String, font: UIFont, color: UIColor, leadingInset: CGFloat,
                   forceScroll: Bool, reduceMotion: Bool, isActive: Bool) {
        let contentChanged = label.text != text || label.font != font || self.leadingInset != leadingInset
        let motionChanged = self.reduceMotion != reduceMotion
        label.text = text
        label.font = font
        label.textColor = color
        self.leadingInset = max(0, leadingInset)
        self.reduceMotion = reduceMotion
        self.isActive = isActive
        // forceScroll remains a layout hint. Never animate fitting content;
        // the measured glyphs and the rendered label now use the same font.
        if contentChanged || motionChanged {
            stop()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
        updatePlayback()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { updatePlayback(); return }

        let width = label.intrinsicContentSize.width
        let distance = reduceMotion ? 0 : MarqueeCycle.distance(
            contentWidth: width, viewportWidth: bounds.width, leadingInset: leadingInset
        )
        let resized = abs(viewportWidth - bounds.width) > 0.5
        let oldCycle = cycle
        let elapsed = cycleElapsed
        let displayedOffset = label.layer.presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat
        // Retain the last reconciled width so subpixel changes accumulate
        // during interactive resizing instead of escaping the tolerance.
        if resized { viewportWidth = bounds.width }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.bounds = CGRect(x: 0, y: 0,
                              width: distance > 0 || oldCycle != nil ? width : max(0, bounds.width - leadingInset),
                              height: intrinsicContentSize.height)
        label.center = CGPoint(x: leadingInset + label.bounds.width / 2, y: bounds.height / 2)
        if resized, let oldCycle {
            let remainder = oldCycle.remainder(at: elapsed, distance: distance, displayedOffset: displayedOffset)
            install(remainder, repeats: false)
        } else if cycle == nil, distance > 0 {
            install(MarqueeCycle(distance: distance), repeats: true)
        }
        CATransaction.commit()
        updatePlayback()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    private var layerTime: CFTimeInterval { label.layer.convertTime(clock(), from: nil) }

    private var cycleElapsed: Double {
        guard let cycle else { return 0 }
        let elapsed = max(0, layerTime - cycleStart)
        return repeats ? elapsed.truncatingRemainder(dividingBy: cycle.duration) : min(elapsed, cycle.duration)
    }

    private func install(_ cycle: MarqueeCycle, repeats: Bool) {
        animationGeneration += 1
        self.cycle = cycle
        self.repeats = repeats
        cycleStart = layerTime
        let animation = cycle.animation(repeats: repeats)
        animation.beginTime = cycleStart
        if !repeats {
            animation.delegate = self
            animation.setValue(animationGeneration, forKey: "generation")
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        label.layer.add(animation, forKey: Self.animationKey)
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag, anim.value(forKey: "generation") as? Int == animationGeneration else { return }
        // The completed resize continuation resets at this normal cycle
        // boundary; the next loop uses the viewport's final dimensions.
        stop()
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func updatePlayback() {
        let shouldPlay = isActive && window != nil && bounds.width > 0 && !reduceMotion
        if !shouldPlay, label.layer.speed != 0 {
            let pausedTime = layerTime
            label.layer.speed = 0
            label.layer.timeOffset = pausedTime
        } else if shouldPlay, label.layer.speed == 0 {
            let pausedTime = label.layer.timeOffset
            label.layer.speed = 1
            label.layer.timeOffset = 0
            label.layer.beginTime = 0
            label.layer.beginTime = layerTime - pausedTime
        }
    }

    func stop() {
        animationGeneration += 1
        cycle = nil
        label.layer.removeAnimation(forKey: Self.animationKey)
    }
}

#Preview("Long and fitting destinations") {
    VStack(spacing: 20) {
        OverflowMarqueeText(text: "Luxembourg, Gare Centrale", font: .body.weight(.semibold))
        OverflowMarqueeText(text: "Kirchberg, Gare routière Luxexpo — via Aéroport", font: .body.weight(.semibold))
        OverflowMarqueeText(text: "Clervaux", font: .body.weight(.semibold))
    }
    .frame(width: 200)
    .padding()
}
