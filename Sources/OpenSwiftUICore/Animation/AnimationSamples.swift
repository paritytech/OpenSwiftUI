//
//  AnimationSamples.swift
//  OpenSwiftUICore
//
//  Describing an animation ahead of time, for a host that can run animations by itself.
//
//  The engine samples every animation in the app, frame by frame, and that does not change.
//  For a host that asks (`AnimationDescriptions.areWanted`), an animation that starts or
//  changes course also has every value it will take from then on worked out. The values
//  travel in the display list, on the item they move or fade (`DisplayList.Ahead`). The host
//  hands them to its compositor and from then on ignores what the engine samples for that
//  item, so the picture keeps moving however busy the app is.
//
//  Described: where an item is, and the value of a renderer effect such as opacity. An item's
//  place is described when it is known what the item is placed from: an origin that does not
//  move (the root, the inside of a geometry group or of a geometry effect), or the animated
//  position of a view around it, when whoever placed it from there said so
//  (`_ViewInputs.setContainerPosition(animatedPositionOf:)`).
//
//  Not described: sizes, the contents of a leaf (a colour that changes), and animations that
//  do not end, such as one that repeats for ever.
//
//  A description is not an attribute, and the value it describes need not change when the
//  description is made: an animation holds its first value for a frame or two, or for as long
//  as its delay. So that the display list still hears of it at once, the rules that attach
//  descriptions depend on a seed that changes when what a value is heading for does
//  (`PositionSamples.seed`).

package import Foundation
package import OpenAttributeGraphShims

// MARK: - AnimationSamples

/// The values an animation will take, `step` seconds apart, the first being its value at
/// `time`, and the last where it comes to rest. When the animation repeats for ever, they are
/// one round of it instead, begun at `time`, which may be past: after the last value the
/// round starts over from the first.
package struct AnimationSamples<Data> {
    /// Changes whenever the animation starts again or changes course. No two descriptions
    /// share one, whichever animations they are of.
    package var seed: UInt32
    package var time: Time
    package var step: Double
    package var values: [Data]
    package var repeats = false

    /// How far ahead an animation is described. One that has not ended by then is not
    /// described at all.
    package static var limit: Int { 600 }

    package static var step: Double { 1.0 / 60.0 }

    package static func makeSeed() -> UInt32 {
        animationSamplesSeed.withLock { seed in
            seed &+= 1
            return seed
        }
    }
}

private let animationSamplesSeed = AnimationSamplesSeed()

private final class AnimationSamplesSeed {
    private let lock = NSLock()
    private var last: UInt32 = 0

    func withLock<T>(_ body: (inout UInt32) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&last)
    }
}

/// Where an animatable attribute leaves the description of the animation it is running, for
/// the display list rule that shows its value.
package final class AnimationSamplesBox<Data> {
    /// An animation is running. Without `samples`, it is one that is not described, and
    /// the value is going somewhere nothing here can tell.
    package var isAnimating = false
    package var samples: AnimationSamples<Data>?

    package init() {}

    /// Changes with the description, and with whether there is anything to describe.
    fileprivate var word: UInt32 {
        samples?.seed ?? (isAnimating ? .max : 0)
    }
}

/// The descriptions that say where a view will be drawn: of its own position, and of the
/// position of what it is placed from.
package final class PositionSamples {
    package enum Container {
        /// An origin that does not move.
        case fixed
        /// The animated position of a view around this one.
        case animated(AnimationSamplesBox<ViewFrame.AnimatableData>)
        /// Something nothing here can tell about.
        case unknown
    }

    package let own: AnimationSamplesBox<ViewFrame.AnimatableData>
    package let container: Container
    /// Changes when either description may have. Reading it makes the reader depend on what
    /// the positions are heading for, and brings both descriptions up to date.
    package let seed: Attribute<UInt32>
    /// Whether the view moves within its container, for the pair of descriptions with these
    /// seeds. Kept because it takes every value to find out.
    fileprivate var movesInContainer: (own: UInt32, container: UInt32, moves: Bool)?

    fileprivate init(
        own: AnimationSamplesBox<ViewFrame.AnimatableData>,
        container: Container,
        seed: Attribute<UInt32>
    ) {
        self.own = own
        self.container = container
        self.seed = seed
    }
}

/// The seed of the descriptions a position is drawn from; see `PositionSamples.seed`.
private struct PositionSamplesSeed: Rule, AsyncAttribute {
    /// What the position is heading for. A description is made when this changes.
    @Attribute var model: ViewOrigin
    /// Where the position is. Reading it brings its description up to date.
    @Attribute var animated: ViewOrigin
    @OptionalAttribute var containerModel: ViewOrigin?
    @OptionalAttribute var container: ViewOrigin?
    let own: AnimationSamplesBox<ViewFrame.AnimatableData>
    let containerBox: AnimationSamplesBox<ViewFrame.AnimatableData>?

    var value: UInt32 {
        _ = (model, containerModel)
        _ = (animated, container)
        return own.word &* 0x9E37_79B1 &+ (containerBox?.word ?? 0)
    }
}

/// The seed of the description of an animated value, for a rule to depend on; see
/// `PositionSamples.seed`.
package struct AnimationSamplesSeedRule<Value>: Rule, AsyncAttribute where Value: Animatable {
    @Attribute var model: Value
    @Attribute var animated: Value
    let box: AnimationSamplesBox<Value.AnimatableData>

    package init(model: Attribute<Value>, animated: Attribute<Value>, box: AnimationSamplesBox<Value.AnimatableData>) {
        _model = model
        _animated = animated
        self.box = box
    }

    package var value: UInt32 {
        _ = (model, animated)
        return box.word
    }
}

// MARK: - AnimationDescriptions

package enum AnimationDescriptions {
    /// The host runs animations by itself and wants them described; see `AnimationSamples`.
    /// It is set before the first view graph is made and not changed after: views are built
    /// differently for it.
    nonisolated(unsafe) package static var areWanted = false
}

// MARK: - DisplayList.Ahead

extension DisplayList {
    /// What will happen to an item, as far as it has been described.
    package final class Ahead {
        /// One property's values to come, the first being the value at `time`; when
        /// `repeats`, one round of values, begun at `time`, that starts over for ever. They
        /// are worked out only when asked for: the host asks once for each `seed`.
        package struct Track<Value> {
            package var seed: UInt32
            package var time: Time
            package var step: Double
            package var repeats: Bool
            package var values: () -> [Value]

            package init(
                seed: UInt32,
                time: Time,
                step: Double,
                repeats: Bool = false,
                values: @escaping () -> [Value]
            ) {
                self.seed = seed
                self.time = time
                self.step = step
                self.repeats = repeats
                self.values = values
            }
        }

        /// What is known of where an item is going.
        package enum Motion {
            /// Nowhere: no animation moves it.
            case still
            /// Somewhere that is not described, or that nothing here can tell. Only the
            /// engine's samples say where it is.
            case sampled
            case described(Track<CGPoint>)
        }

        /// Where the item's origin will be, in the coordinates its frame is in.
        package let origin: Track<CGPoint>?
        /// The origin is moving, or may be, without `origin` saying how.
        package let originIsSampled: Bool
        /// For an effect item, the effect's values.
        package let effect: Track<DisplayList.Effect>?

        private init(origin: Track<CGPoint>?, originIsSampled: Bool, effect: Track<DisplayList.Effect>?) {
            self.origin = origin
            self.originIsSampled = originIsSampled
            self.effect = effect
        }

        private static let sampled = Ahead(origin: nil, originIsSampled: true, effect: nil)

        /// Nil when there is nothing to say: the item stays where it is and as it is.
        package static func make(origin: Motion, effect: Track<DisplayList.Effect>?) -> Ahead? {
            switch origin {
            case .still:
                effect == nil ? nil : Ahead(origin: nil, originIsSampled: false, effect: effect)
            case .sampled:
                effect == nil ? sampled : Ahead(origin: nil, originIsSampled: true, effect: effect)
            case let .described(track):
                Ahead(origin: track, originIsSampled: false, effect: effect)
            }
        }

        /// Where an item is going whose origin is now `offset` away from the animated
        /// position `samples` are for, itself placed from `containerPosition`. To be called
        /// while a rule is evaluated: the rule comes to depend on the descriptions.
        package static func motion(
            _ samples: PositionSamples?,
            offset: CGSize,
            containerPosition: CGPoint
        ) -> Motion {
            guard let samples else {
                // Descriptions are not wanted.
                return .still
            }
            _ = samples.seed.value
            let containerBox: AnimationSamplesBox<ViewFrame.AnimatableData>?
            switch samples.container {
            case .fixed: containerBox = nil
            case let .animated(box): containerBox = box
            case .unknown: return .sampled
            }
            guard let own = samples.own.samples else {
                return samples.own.isAnimating || containerBox?.isAnimating == true ? .sampled : .still
            }
            func origin(_ data: ViewFrame.AnimatableData) -> CGPoint {
                var origin = ViewOrigin()
                origin.animatableData = data.first
                return origin
            }
            guard let containerBox, containerBox.isAnimating else {
                return .described(Track(seed: own.seed, time: own.time, step: own.step, repeats: own.repeats) {
                    own.values.map { origin($0) + offset }
                })
            }
            guard let container = containerBox.samples, !own.repeats, !container.repeats else {
                // Not described, or two movements of which one comes round for ever: one
                // list of values cannot say where that leaves the item.
                return .sampled
            }
            // Both move. The two descriptions may have been made at different times: they
            // are lined up from the later one on, each staying at its last value once over.
            let lead = Int(((container.time - own.time) / own.step).rounded())
            let ownStart = max(lead, 0), containerStart = max(-lead, 0)
            let count = max(own.values.count - ownStart, container.values.count - containerStart, 1)
            // The item's origin is its position less the container's, and whatever else
            // separates them now.
            let rest = CGSize(
                width: offset.width + containerPosition.x,
                height: offset.height + containerPosition.y
            )
            func value(at index: Int) -> CGPoint {
                let position = origin(own.values[min(ownStart + index, own.values.count - 1)])
                let base = origin(container.values[min(containerStart + index, container.values.count - 1)])
                return CGPoint(x: position.x - base.x + rest.width, y: position.y - base.y + rest.height)
            }
            // A view carried along by its container does not move within it.
            let moves: Bool
            if let known = samples.movesInContainer, known.own == own.seed, known.container == container.seed {
                moves = known.moves
            } else {
                let last = value(at: count - 1)
                moves = (0 ..< count).contains { index in
                    let point = value(at: index)
                    return abs(point.x - last.x) > 0.01 || abs(point.y - last.y) > 0.01
                }
                samples.movesInContainer = (own.seed, container.seed, moves)
            }
            guard moves else {
                return .still
            }
            return .described(Track(
                seed: own.seed &* 0x9E37_79B1 &+ container.seed,
                time: max(own.time, container.time),
                step: own.step
            ) {
                (0 ..< count).map(value(at:))
            })
        }

        /// The description of the one item that an item placed at `outerOrigin` and the
        /// only item inside it, placed at `innerOrigin`, become when they are merged.
        package static func merging(
            _ outer: Ahead?,
            at outerOrigin: CGPoint,
            with inner: Ahead?,
            at innerOrigin: CGPoint
        ) -> Ahead? {
            let motion: Motion
            switch (outer?.origin, inner?.origin) {
            case _ where outer?.originIsSampled == true || inner?.originIsSampled == true:
                motion = .sampled
            case (nil, nil):
                motion = .still
            // The values are for another place than before, so the seed is another too.
            case let (track?, nil):
                motion = .described(Track(
                    seed: track.seed &* 0x85EB_CA6B &+ 1, time: track.time, step: track.step, repeats: track.repeats
                ) {
                    track.values().map { CGPoint(x: $0.x + innerOrigin.x, y: $0.y + innerOrigin.y) }
                })
            case let (nil, track?):
                motion = .described(Track(
                    seed: track.seed &* 0x85EB_CA6B &+ 2, time: track.time, step: track.step, repeats: track.repeats
                ) {
                    track.values().map { CGPoint(x: $0.x + outerOrigin.x, y: $0.y + outerOrigin.y) }
                })
            case (_?, _?):
                // Both moving: where the merged item is depends on two animations, which
                // one track cannot say.
                motion = .sampled
            }
            return make(origin: motion, effect: inner?.effect)
        }
    }
}

// MARK: - _ViewInputs

extension _ViewInputs {
    /// The animated position and, when descriptions are wanted, the ones that say where the
    /// view will be drawn.
    package func describedAnimatedPosition() -> (position: Attribute<ViewOrigin>, samples: PositionSamples?) {
        let (position, own) = animatedPositionAndSamples()
        guard let own else {
            return (position, nil)
        }
        let container: PositionSamples.Container
        var containerModel = OptionalAttribute<ViewOrigin>()
        var containerAnimated = OptionalAttribute<ViewOrigin>()
        var containerBox: AnimationSamplesBox<ViewFrame.AnimatableData>?
        if containerPosition.identifier == ViewGraph.current.$zeroPoint.identifier {
            container = .fixed
        } else if let known = containerPositionSamples, known.position == containerPosition.identifier {
            container = .animated(known.samples)
            containerModel = OptionalAttribute(known.model)
            containerAnimated = OptionalAttribute(containerPosition)
            containerBox = known.samples
        } else {
            container = .unknown
        }
        let seed = Attribute(PositionSamplesSeed(
            model: self.position,
            animated: position,
            containerModel: containerModel,
            container: containerAnimated,
            own: own,
            containerBox: containerBox
        ))
        return (position, PositionSamples(own: own, container: container, seed: seed))
    }

    /// The animated position and, when descriptions are wanted, where the animation it is
    /// running is described. The two come from one call because a later call may be
    /// answered by a different attribute.
    package func animatedPositionAndSamples() -> (
        position: Attribute<ViewOrigin>,
        samples: AnimationSamplesBox<ViewFrame.AnimatableData>?
    ) {
        base.cachedEnvironment.wrappedValue.animatedPositionAndSamples(for: self)
    }

    /// Places the views inside from this view's animated position, and says so, so that
    /// where they are drawn can be described; see `AnimationSamples`.
    package mutating func setContainerPosition(animatedPositionOf inputs: _ViewInputs) {
        let (position, samples) = inputs.animatedPositionAndSamples()
        containerPosition = position
        containerPositionSamples = samples.map { (position.identifier, $0, inputs.position) }
    }
}
