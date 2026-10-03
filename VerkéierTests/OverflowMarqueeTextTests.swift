import QuartzCore
import SwiftUI
import Testing
import UIKit
@testable import Verkeier

@Suite("Destination marquee timing")
struct MarqueeCycleTests {
    @Test func onlyScrollsActualOverflow() {
        #expect(MarqueeCycle.distance(contentWidth: 100, viewportWidth: 100, leadingInset: 0) == 0)
        #expect(MarqueeCycle.distance(contentWidth: 101, viewportWidth: 100, leadingInset: 0) == 0)
        #expect(MarqueeCycle.distance(contentWidth: 150, viewportWidth: 100, leadingInset: 10) == 60)
        #expect(MarqueeCycle.distance(contentWidth: 150, viewportWidth: 0, leadingInset: 0) == 0)
        #expect(MarqueeCycle.distance(contentWidth: 0, viewportWidth: 100, leadingInset: 0) == 0)
    }

    @Test func pausesAndMovesAtConstantSpeed() {
        let cycle = MarqueeCycle(distance: 140)
        #expect(cycle.movementDuration == 4)
        #expect(cycle.duration == 7)
        #expect(cycle.offset(at: 0) == 0)
        #expect(cycle.offset(at: 1.5) == 0)
        #expect(cycle.offset(at: 2.5) == -35)
        #expect(cycle.offset(at: 3.5) == -70)
        #expect(cycle.offset(at: 5.5) == -140)
        #expect(cycle.offset(at: 6.9) == -140)
    }

    @Test func loopResetsWithoutRightwardKeyframes() throws {
        let cycle = MarqueeCycle(distance: 140)
        let animation = cycle.animation(repeats: true)
        let values = try #require(animation.values as? [CGFloat])
        #expect(values == [0, 0, -140, -140])
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(animation.repeatCount == .infinity)
        #expect(animation.calculationMode == .linear)
        #expect(animation.duration == cycle.duration)
        #expect(cycle.offset(at: cycle.duration.truncatingRemainder(dividingBy: cycle.duration)) == 0)
    }

    @Test func shrinkingViewportContinuesLeftFromCurrentPosition() {
        let original = MarqueeCycle(distance: 140)
        let remainder = original.remainder(at: 3.5, distance: 210)
        #expect(remainder.startOffset == -70)
        #expect(remainder.endOffset == -210)
        #expect(remainder.startPause == 0)
        #expect(remainder.movementDuration == 4)
        #expect(remainder.offset(at: 1) == -105)
    }

    @Test func growingViewportNeverReverses() {
        let original = MarqueeCycle(distance: 140)
        let remainder = original.remainder(at: 3.5, distance: 35)
        #expect(remainder.startOffset == -70)
        #expect(remainder.endOffset == -70)
        #expect(remainder.movementDuration == 0)
        #expect(remainder.endPause == 1.5)
    }

    @Test func resizePreservesRemainingReadingPause() {
        let original = MarqueeCycle(distance: 140)
        #expect(original.remainder(at: 1, distance: 210).startPause == 0.5)
        let end = original.remainder(at: 6, distance: 100)
        #expect(end.startOffset == -140)
        #expect(end.endPause == 1)
        let extended = original.remainder(at: 6, distance: 210)
        #expect(extended.endOffset == -210)
        #expect(extended.endPause == 1.5)
    }
}

@MainActor
@Suite("Destination marquee lifecycle")
struct MarqueeLabelViewTests {
    private let destination = "Kirchberg, Gare routière Luxexpo — via Aéroport"

    private func configure(_ view: MarqueeLabelView, text: String? = nil, font: UIFont? = nil,
                           color: UIColor = .label, reduceMotion: Bool = false, active: Bool = true,
                           forceScroll: Bool = false) {
        view.configure(text: text ?? destination, font: font ?? .preferredFont(forTextStyle: .body),
                       color: color, leadingInset: 0, forceScroll: forceScroll,
                       reduceMotion: reduceMotion, isActive: active)
        view.layoutIfNeeded()
    }

    private func label(in view: MarqueeLabelView) throws -> UILabel {
        try #require(view.subviews.first as? UILabel)
    }

    private func host(_ view: MarqueeLabelView) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        view.frame = CGRect(x: 0, y: 0, width: 120, height: 30)
        window.addSubview(view)
        return window
    }

    @Test func unchangedUpdatesAndHeightChangesPreserveCycle() throws {
        let view = MarqueeLabelView()
        let window = try host(view)
        defer { view.stop(); view.removeFromSuperview(); _ = window }
        configure(view)
        let generation = view.animationGeneration
        let originalCycle = try #require(view.cycle)
        let beginTime = try #require(label(in: view).layer.animation(forKey: MarqueeLabelView.animationKey)).beginTime
        configure(view, color: .black)
        view.frame.size.height = 80
        view.layoutIfNeeded()
        #expect(view.animationGeneration == generation)
        #expect(view.cycle == originalCycle)
        #expect(try label(in: view).layer.animation(forKey: MarqueeLabelView.animationKey)?.beginTime == beginTime)
        #expect(try label(in: view).center.y == 40)
    }

    @Test func fittingLabelsStayStationaryEvenWhenForced() throws {
        let view = MarqueeLabelView()
        let window = try host(view)
        defer { view.stop(); view.removeFromSuperview(); _ = window }
        configure(view, text: "Clervaux", forceScroll: true)
        #expect(view.cycle == nil)
    }

    @Test func contentAndFontChangesStartFreshCycles() throws {
        let view = MarqueeLabelView()
        let window = try host(view)
        defer { view.stop(); view.removeFromSuperview(); _ = window }
        configure(view)
        let original = view.animationGeneration
        configure(view, text: destination + " (terminus)")
        #expect(view.animationGeneration > original)
        #expect(view.cycle?.startOffset == 0)
        let changedText = view.animationGeneration
        configure(view, font: .preferredFont(forTextStyle: .body,
                                          compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)))
        #expect(view.animationGeneration > changedText)
        #expect(view.cycle?.startOffset == 0)
        #expect(view.intrinsicContentSize.height > 30)
        #expect(try label(in: view).isAccessibilityElement == false)
    }

    @Test func resizingUsesOneShotContinuationThenCorrectFinalWidth() throws {
        var now: CFTimeInterval = 100
        let view = MarqueeLabelView(clock: { now })
        let window = try host(view)
        defer { view.stop(); view.removeFromSuperview(); _ = window }
        configure(view)
        now += 2.5
        view.frame.size.width = 90
        view.layoutIfNeeded()
        let continued = try #require(view.cycle)
        #expect(continued.startOffset == -35)
        #expect(continued.startPause == 0)
        let animation = try #require(label(in: view).layer.animation(forKey: MarqueeLabelView.animationKey))
        #expect(animation.repeatCount == 0)
        view.animationDidStop(animation, finished: true)
        #expect(view.cycle?.startOffset == 0)
        #expect(try view.cycle?.endOffset == -(label(in: view).intrinsicContentSize.width - 90))
        #expect(try label(in: view).layer.animation(forKey: MarqueeLabelView.animationKey)?.repeatCount == .infinity)
    }

    @Test func reduceMotionAndTeardownRemoveAnimations() throws {
        let view = MarqueeLabelView()
        let window = try host(view)
        defer { view.stop(); view.removeFromSuperview(); _ = window }
        configure(view)
        #expect(view.cycle != nil)
        configure(view, reduceMotion: true)
        #expect(view.cycle == nil)
        #expect(try label(in: view).layer.animationKeys() == nil)
        #expect(try label(in: view).bounds.width == 120)
        #expect(try label(in: view).lineBreakMode == .byTruncatingTail)
        configure(view)
        #expect(view.cycle != nil)
        view.stop()
        #expect(try label(in: view).layer.animationKeys() == nil)
    }

    @Test func offscreenAndInactiveTimeDoNotAdvanceCycle() throws {
        var now: CFTimeInterval = 100
        let view = MarqueeLabelView(clock: { now })
        let window = try host(view)
        defer { view.stop(); view.removeFromSuperview(); _ = window }
        configure(view)
        let generation = view.animationGeneration
        now += 2.5
        configure(view, active: false)
        let paused = try label(in: view).layer.timeOffset
        #expect(try label(in: view).layer.speed == 0)
        now += 60
        configure(view)
        #expect(try label(in: view).layer.speed == 1)
        #expect(try label(in: view).layer.convertTime(now, from: nil) == paused)
        #expect(view.animationGeneration == generation)
        view.removeFromSuperview()
        #expect(try label(in: view).layer.speed == 0)
        now += 60
        window.addSubview(view)
        #expect(try label(in: view).layer.convertTime(now, from: nil) == paused)
        #expect(view.animationGeneration == generation)
    }

    @Test func staleCompletionCannotRestartNewContent() throws {
        let view = MarqueeLabelView()
        let window = try host(view)
        defer { view.stop(); view.removeFromSuperview(); _ = window }
        configure(view)
        view.frame.size.width = 90
        view.layoutIfNeeded()
        let stale = try #require(label(in: view).layer.animation(forKey: MarqueeLabelView.animationKey))
        configure(view, text: "Clervaux")
        let generation = view.animationGeneration
        view.animationDidStop(stale, finished: true)
        #expect(view.animationGeneration == generation)
        #expect(view.cycle == nil)
    }

    @Test func dynamicTypeFontResolvesIdenticallyForNativeLabel() {
        var environment = EnvironmentValues()
        environment.dynamicTypeSize = .accessibility3
        let font = Font.body.weight(.semibold).resolve(in: environment.fontResolutionContext)
        let native = font.ctFont as UIFont
        #expect(native.pointSize == font.pointSize)
        #expect(native.pointSize > UIFont.preferredFont(forTextStyle: .body).pointSize)
    }
}
