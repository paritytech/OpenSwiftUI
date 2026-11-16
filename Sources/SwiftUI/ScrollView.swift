//
//  ScrollView.swift
//  SwiftUI
//
//  A scrollable container written against OpenSwiftUI's public API only. Apple's ScrollView is
//  backed by UIScrollView; there is no such platform view on Linux, so dragging, deceleration and
//  the bounce at the ends are implemented here with gestures, layout and animations.
//
//  Not implemented: scroll indicators, wheel and trackpad scrolling, ScrollViewReader, paging.
//  A touch that stops moving content also reaches the content under it.

import Foundation
public import OpenSwiftUI

public struct ScrollView<Content>: View where Content: View {
    public var content: Content
    public var axes: Axis.Set
    public var showsIndicators: Bool

    /// Where the content is going: the distance scrolled from its leading and top edges.
    /// While an animation runs, the content on screen has not reached this yet.
    @State private var offset: CGSize = .zero
    /// The offset on screen when the current drag began; nil when no drag is under way.
    @State private var dragOrigin: CGSize?
    @State private var contentSize: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var presentation = ScrollPresentation()
    /// Set by a NavigationStack for a screen with a large title.
    @Environment(\.navigationLargeTitle) private var largeTitle
    /// This scroll view begins right under the space left for the large title, so it takes
    /// the title over: it extends up into that space and draws the title above its content.
    @State private var isUnderLargeTitle = false

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: some View {
        let title = axes.contains(.vertical) && isUnderLargeTitle ? largeTitle : nil
        let titleHeight = title?.height ?? 0
        content
            .environment(\.navigationLargeTitle, nil)
            .padding(.top, titleHeight)
            .overlay(title.map { NavigationLargeTitleView(title: $0.title) }, alignment: .top)
            // The scroll axes get no size limit; the other axis keeps the viewport's.
            .fixedSize(horizontal: axes.contains(.horizontal), vertical: axes.contains(.vertical))
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { contentSize = $0 }
            // One group for the content: scrolling then moves a single item of the display
            // list instead of changing the position of everything in it.
            .geometryGroup()
            .modifier(ScrollOffsetModifier(
                offset: offset,
                presentation: presentation,
                // The title counts as gone a little before its last pixels are.
                titleCollapse: title.map { $0.height - 12 }
            ))
            // A flexible frame is never smaller than its content unless the minimum says so;
            // with it, the viewport is exactly what the parent proposes.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { viewportSize = $0 }
            .clipped()
            .contentShape(Rectangle())
            .gesture(drag)
            .simultaneousGesture(touch)
            .onChange(of: limit) { _, limit in
                // Content or viewport changed size: stay within what can now be shown.
                if dragOrigin == nil, offset != offset.clamped(to: limit) {
                    jump(to: offset.clamped(to: limit))
                }
            }
            .padding(.top, -titleHeight)
            // Measured outside the padding, so taking the title over does not change it.
            .onGeometryChange(for: Bool.self, of: { [largeTitle] proxy in
                guard let largeTitle else { return false }
                return abs(proxy.frame(in: .global).minY - (largeTitle.top + largeTitle.height)) < 1
            }) { isUnderLargeTitle = $0 }
            .preference(key: NavigationScrollShowsTitleKey.self, value: title != nil)
    }

    /// The farthest the content can scroll on each axis.
    private var limit: CGSize {
        CGSize(
            width: axes.contains(.horizontal) ? max(contentSize.width - viewportSize.width, 0) : 0,
            height: axes.contains(.vertical) ? max(contentSize.height - viewportSize.height, 0) : 0
        )
    }

    /// Follows the finger once it has moved far enough to mean a scroll rather than a tap.
    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                let origin = dragOrigin ?? presentation.offset
                dragOrigin = origin
                let raw = CGSize(
                    width: axes.contains(.horizontal) ? origin.width - value.translation.width : 0,
                    height: axes.contains(.vertical) ? origin.height - value.translation.height : 0
                )
                presentation.lastMove = value.time
                jump(to: raw.rubberBanded(to: limit, viewport: viewportSize))
            }
            .onEnded { value in
                dragOrigin = nil
                // A finger that stopped before lifting sends no more movement, so the gesture
                // still reports the speed it last had. Lifting after a pause is not a flick.
                let paused = value.time.timeIntervalSince(presentation.lastMove ?? value.time) > flickTimeout
                release(velocity: paused ? .zero : CGSize(
                    width: axes.contains(.horizontal) ? -value.velocity.width : 0,
                    height: axes.contains(.vertical) ? -value.velocity.height : 0
                ))
            }
    }

    /// Sees every touch from the moment it lands: moving content stops under the finger, and
    /// content left past an end by a touch that never became a drag goes back when it lifts.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if dragOrigin == nil, presentation.offset != offset {
                    jump(to: presentation.offset)
                }
            }
            .onEnded { _ in
                if dragOrigin == nil, offset != offset.clamped(to: limit) {
                    release(velocity: .zero)
                }
            }
    }

    /// Lets go of the content moving at `velocity` points per second.
    private func release(velocity: CGSize) {
        // Two touches reported for the same instant make a speed that is infinite or not a
        // number at all. Nothing real scrolls faster than this.
        func bounded(_ speed: CGFloat) -> CGFloat {
            speed.isNaN ? 0 : min(max(speed, -maximumFlickSpeed), maximumFlickSpeed)
        }
        let velocity = CGSize(width: bounded(velocity.width), height: bounded(velocity.height))
        let coast = CGSize(
            width: offset.width + velocity.width / ScrollDeceleration.rate,
            height: offset.height + velocity.height / ScrollDeceleration.rate
        )
        let target = coast.clamped(to: limit)
        if target == coast {
            withAnimation(Animation(ScrollDeceleration())) { offset = coast }
            return
        }
        // The content is past an end or would coast past it: a spring takes it to the end,
        // carrying the release velocity, so a fast flick overshoots and comes back.
        let delta = CGSize(width: target.width - offset.width, height: target.height - offset.height)
        let distanceSquared = delta.width * delta.width + delta.height * delta.height
        guard distanceSquared > 0.01 else {
            jump(to: target)
            return
        }
        let speedAlongDelta = (velocity.width * delta.width + velocity.height * delta.height) / distanceSquared
        withAnimation(Animation(ScrollBounce(initialVelocity: speedAlongDelta))) { offset = target }
    }

    /// Puts the content at `newOffset` now, replacing any animation in flight.
    ///
    /// A plain state change would not do that: an animation already running keeps playing out
    /// on top of the new value.
    private func jump(to newOffset: CGSize) {
        withAnimation(Animation(ScrollJump())) { offset = newOffset }
    }
}

/// How long after the last movement a lift still counts as a flick, in seconds.
private let flickTimeout: TimeInterval = 0.1
/// The fastest a flick is taken to be, in points per second.
private let maximumFlickSpeed: CGFloat = 20_000

// MARK: - Presentation

/// What is on screen and when it last followed the finger, kept outside view state because it
/// changes every frame and nothing needs to redraw for it.
private final class ScrollPresentation {
    /// The offset currently shown. During an animation it lags the view's state, which
    /// already holds the destination.
    var offset: CGSize = .zero
    /// When the current drag last moved the content.
    var lastMove: Date?
}

private struct ScrollOffsetModifier: ViewModifier, Animatable {
    var offset: CGSize
    let presentation: ScrollPresentation
    /// How far the content scrolls before a large title above it is out of sight.
    var titleCollapse: CGFloat?

    var animatableData: CGSize.AnimatableData {
        get { offset.animatableData }
        set { offset.animatableData = newValue }
    }

    func body(content: Content) -> some View {
        // Evaluated for every animation frame with the interpolated offset.
        presentation.offset = offset
        return content
            .offset(x: -offset.width, y: -offset.height)
            .preference(key: NavigationTitleCollapsedKey.self, value: titleCollapse.map { offset.height >= $0 } ?? false)
    }
}

// MARK: - Motion

/// Arrives at once, and takes over from whatever animation was running.
private struct ScrollJump: CustomAnimation {
    func animate<V>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? where V: VectorArithmetic {
        nil
    }

    func shouldMerge<V>(
        previous: Animation,
        value: V,
        time: TimeInterval,
        context: inout AnimationContext<V>
    ) -> Bool where V: VectorArithmetic {
        true
    }
}

/// Coasting after a flick: velocity decays exponentially, as UIScrollView's does at its normal
/// deceleration rate (0.998 per millisecond).
private struct ScrollDeceleration: CustomAnimation {
    /// Decay per second: -1000 * ln(0.998). A release at `v` points per second travels `v / rate`.
    static let rate = 2.002

    func animate<V>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? where V: VectorArithmetic {
        let remaining = exp(-Self.rate * time)
        // Stop once less than half a point of travel is left.
        guard remaining * remaining * value.magnitudeSquared > 0.25 else { return nil }
        return value.scaled(by: 1 - remaining)
    }
}

/// A critically damped spring to the end of the content, started with the release velocity.
private struct ScrollBounce: CustomAnimation {
    /// Velocity along the path to the destination, in path lengths per second.
    var initialVelocity: Double
    private static let frequency = 12.0

    func animate<V>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? where V: VectorArithmetic {
        let decay = exp(-Self.frequency * time)
        let remaining = decay * (1 + (Self.frequency - initialVelocity) * time)
        // Settled when both the distance left and the envelope that bounds any overshoot are
        // under half a point.
        let envelope = decay * (1 + abs(Self.frequency - initialVelocity) * time)
        guard envelope * envelope * value.magnitudeSquared > 0.25 else { return nil }
        return value.scaled(by: 1 - remaining)
    }
}

// MARK: - Geometry

private extension CGSize {
    func clamped(to limit: CGSize) -> CGSize {
        CGSize(width: min(max(width, 0), limit.width), height: min(max(height, 0), limit.height))
    }

    /// Resists movement past either end, the way UIScrollView does: the farther the drag goes
    /// beyond the end, the less the content follows; it never moves more than one viewport.
    func rubberBanded(to limit: CGSize, viewport: CGSize) -> CGSize {
        CGSize(
            width: Self.rubberBand(width, limit: limit.width, dimension: viewport.width),
            height: Self.rubberBand(height, limit: limit.height, dimension: viewport.height)
        )
    }

    private static func rubberBand(_ value: CGFloat, limit: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0 else { return min(max(value, 0), limit) }
        func stretch(_ overshoot: CGFloat) -> CGFloat {
            (1 - 1 / (overshoot * 0.55 / dimension + 1)) * dimension
        }
        if value < 0 { return -stretch(-value) }
        if value > limit { return limit + stretch(value - limit) }
        return value
    }
}
