//
//  AnimatableAttribute.swift
//  OpenSwiftUICore
//
//  Audited for 6.5.4
//  Status: Blocked by Trace
//  ID: 35ADF281214A25133F1A6DF28858952D (SwiftUICore)

package import Foundation
package import OpenAttributeGraphShims

// MARK: - AnimatableAttribute

package struct AnimatableAttribute<Value>: StatefulRule, AsyncAttribute, ObservedAttribute, CustomStringConvertible where Value: Animatable {
    @Attribute var source: Value
    @Attribute var environment: EnvironmentValues
    var helper: AnimatableAttributeHelper<Value>

    package init(
        source: Attribute<Value>,
        phase: Attribute<_GraphInputs.Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        environment: Attribute<EnvironmentValues>,
        samples: AnimationSamplesBox<Value.AnimatableData>? = nil
    ) {
        _source = source
        _environment = environment
        helper = .init(phase: phase, time: time, transaction: transaction)
        helper.samplesBox = samples
    }

    package mutating func updateValue() {
        var sourceValue = $source.changedValue()
        helper.update(
            value: &sourceValue,
            defaultAnimation: nil,
            environment: $environment
        )
        guard sourceValue.changed || !hasValue else {
            return
        }
        value = sourceValue.value
    }

    package var description: String { "Animatable<\(Value.self)>" }

    package mutating func destroy() {
        helper.removeListeners()
    }
}

// MARK: - AnimatableFrameAttribute

package struct AnimatableFrameAttribute: StatefulRule, AsyncAttribute, ObservedAttribute {
    @Attribute
    private var position: ViewOrigin

    @Attribute
    private var size: ViewSize

    @Attribute
    private var pixelLength: CGFloat

    @Attribute
    private var environment: EnvironmentValues

    private var helper: AnimatableAttributeHelper<ViewFrame>

    let animationsDisabled: Bool

    package init(
        position: Attribute<ViewOrigin>,
        size: Attribute<ViewSize>,
        pixelLength: Attribute<CGFloat>,
        environment: Attribute<EnvironmentValues>,
        phase: Attribute<_GraphInputs.Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        animationsDisabled: Bool,
        samples: AnimationSamplesBox<ViewFrame.AnimatableData>? = nil
    ) {
        _position = position
        _size = size
        _pixelLength = pixelLength
        _environment = environment
        helper = .init(phase: phase, time: time, transaction: transaction)
        helper.samplesBox = samples
        self.animationsDisabled = animationsDisabled
    }

    package typealias Value = ViewFrame

    package mutating func updateValue() {
        let (position, positionChanged) = $position.changedValue()
        let (size, sizeChanged) = $size.changedValue()
        let (pixelLength, pixelLengthChanged) = $pixelLength.changedValue()
        let anyChanged = positionChanged || sizeChanged || pixelLengthChanged
        var rect = CGRect(origin: position, size: size.value)
        rect.roundCoordinatesToNearestOrUp(toMultipleOf: pixelLength)
        let viewFrame = ViewFrame(
            origin: rect.origin,
            size: ViewSize(value: rect.size, proposal: size._proposal)
        )
        var sourceValue = (
            value: viewFrame,
            changed: anyChanged
        )
        if !animationsDisabled {
            helper.update(
                value: &sourceValue,
                defaultAnimation: nil,
                environment: $environment
            )
        }
        guard sourceValue.changed || !hasValue else {
            return
        }
        value = sourceValue.value
    }

    package mutating func destroy() {
        helper.removeListeners()
    }
}

// MARK: - AnimatableFrameAttributeVFD

package struct AnimatableFrameAttributeVFD: StatefulRule, AsyncAttribute, ObservedAttribute {
    @Attribute
    private var position: ViewOrigin

    @Attribute
    private var size: ViewSize

    @Attribute
    private var pixelLength: CGFloat

    @Attribute
    private var environment: EnvironmentValues

    private var helper: AnimatableAttributeHelper<ViewFrame>

    private var velocityFilter: FrameVelocityFilter

    let animationsDisabled: Bool

    package init(
        position: Attribute<ViewOrigin>,
        size: Attribute<ViewSize>,
        pixelLength: Attribute<CGFloat>,
        environment: Attribute<EnvironmentValues>,
        phase: Attribute<_GraphInputs.Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        animationsDisabled: Bool,
        samples: AnimationSamplesBox<ViewFrame.AnimatableData>? = nil
    ) {
        _position = position
        _size = size
        _pixelLength = pixelLength
        _environment = environment
        helper = .init(phase: phase, time: time, transaction: transaction)
        helper.samplesBox = samples
        velocityFilter = FrameVelocityFilter()
        self.animationsDisabled = animationsDisabled
    }

    package typealias Value = ViewFrame

    package mutating func updateValue() {
        let (position, positionChanged) = $position.changedValue()
        let (size, sizeChanged) = $size.changedValue()
        let (pixelLength, pixelLengthChanged) = $pixelLength.changedValue()
        let anyChanged = positionChanged || sizeChanged || pixelLengthChanged
        var rect = CGRect(origin: position, size: size.value)
        rect.roundCoordinatesToNearestOrUp(toMultipleOf: pixelLength)
        let viewFrame = ViewFrame(
            origin: rect.origin,
            size: ViewSize(value: rect.size, proposal: size._proposal)
        )
        var sourceValue = (
            value: viewFrame,
            changed: anyChanged
        )
        if !animationsDisabled {
            helper.update(
                value: &sourceValue,
                defaultAnimation: nil,
                environment: $environment
            )
        }
        guard sourceValue.changed || !hasValue else {
            return
        }
        value = sourceValue.value
    }

    package mutating func destroy() {
        helper.removeListeners()
    }
}

// MARK: - AnimatableAttributeHelper

package struct AnimatableAttributeHelper<Value> where Value: Animatable {
    @Attribute
    package var phase: _GraphInputs.Phase

    @Attribute
    package var time: Time

    @Attribute
    package var transaction: Transaction

    private var previousModelData: Value.AnimatableData? = nil

    private var animatorState: AnimatorState<Value.AnimatableData>? = nil

    private var resetSeed: UInt32 = 0

    /// Where the running animation is described for a host that runs animations by itself;
    /// see `AnimationSamples`. Nil when nothing shows this value in a way a host could animate.
    package var samplesBox: AnimationSamplesBox<Value.AnimatableData>? = nil

    /// What the description in `samplesBox` was made from: it is made again when the
    /// animation changes course or the value it is heading for changes. An animation found
    /// to have no description, such as one that never ends, has none wherever it is heading.
    /// `elapsed` is how far into the animation its first value is.
    private var described: (
        generation: UInt32,
        target: Value.AnimatableData,
        isDescribed: Bool,
        elapsed: Double
    )? = nil

    package init(
        phase: Attribute<_GraphInputs.Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>
    ) {
        _phase = phase
        _time = time
        _transaction = transaction
    }

    package var isAnimating: Bool {
        animatorState != nil
    }

    @inline(__always)
    private mutating func updateAnimatorStateIfNeeded(
        value: (value: Value, changed: Bool),
        defaultAnimation: Animation?,
        animationTime: inout Time,
        environment: Attribute<EnvironmentValues>,
        sampleCollector: (Value.AnimatableData, Time) -> Void
    ) {
        guard value.changed else {
            return
        }
        let modelData = value.value.animatableData
        defer { previousModelData = modelData }
        guard let previousModelData, modelData != previousModelData else {
            return
        }
        let transaction: Transaction = Graph.withoutUpdate { self.transaction }
        guard let animation = transaction.effectiveAnimation ?? defaultAnimation else {
            return
        }
        var interval = modelData
        interval -= previousModelData
        animationTime = time

        let state: AnimatorState<Value.AnimatableData>
        if let animatorState {
            state = animatorState
            animatorState.combine(
                newAnimation: animation,
                newInterval: interval,
                at: animationTime,
                in: transaction,
                environment: environment
            )
            // TODO: CustomEventTrace
        } else {
            state = AnimatorState(
                animation: animation,
                interval: interval,
                at: animationTime,
                in: transaction
            )
            // TODO: CustomEventTrace
            animatorState = state
        }
        state.addListeners(transaction: transaction)
    }

    @inline(__always)
    private mutating func updateValueIfNeeded(
        value: inout (value: Value, changed: Bool),
        animationTime: Time,
        environment: Attribute<EnvironmentValues>,
        sampleCollector: (Value.AnimatableData, Time) -> Void
    ) {
        guard let animatorState else {
            return
        }
        var animatableData = value.value.animatableData
        let isAnimationOver = animatorState.update(
            &animatableData,
            at: animationTime,
            environment: environment
        )
        // let attribute = AnyAttribute.current // For tracing
        if isAnimationOver {
            // TODO: [Trace] CustomEventTrace + OAGGraphAddTraceEvent
            // TODO: Signpost
            removeListeners()
            self.animatorState = nil
        } else {
            // TODO: [Trace] CustomEventTrace + OAGGraphAddTraceEvent
            sampleCollector(animatableData, time)
            animatorState.nextUpdate()
        }
        value.value.animatableData = animatableData
        value.changed = true
    }

    package mutating func update(
        value: inout (value: Value, changed: Bool),
        defaultAnimation: Animation?,
        environment: Attribute<EnvironmentValues>,
        sampleCollector: (Value.AnimatableData, Time) -> Void
    ) {
        var animationTime = -Time.infinity
        if animatorState != nil {
            let (time, timeChanged) = $time.changedValue()
            if timeChanged {
                animationTime = time
            }
        }
        let reseted = checkReset()
        if reseted {
            value.changed = true
        }
        updateAnimatorStateIfNeeded(
            value: value,
            defaultAnimation: defaultAnimation,
            animationTime: &animationTime,
            environment: environment,
            sampleCollector: sampleCollector
        )
        updateValueIfNeeded(
            value: &value,
            animationTime: animationTime,
            environment: environment,
            sampleCollector: sampleCollector
        )
        describeIfNeeded(environment: environment)
    }

    private mutating func describeIfNeeded(environment: Attribute<EnvironmentValues>) {
        guard let samplesBox else {
            return
        }
        guard let animatorState, let target = previousModelData else {
            samplesBox.isAnimating = false
            samplesBox.samples = nil
            described = nil
            return
        }
        samplesBox.isAnimating = true
        if let described, described.generation == animatorState.generation,
           !described.isDescribed || described.target == target {
            // An animation's clock starts when it is first evaluated, and is set again at
            // its second evaluation. The description keeps to that clock.
            if let start = animatorState.startTime, samplesBox.samples != nil {
                samplesBox.samples?.time = start + described.elapsed
            }
            return
        }
        let ahead = animatorState.valuesAhead(
            target: target,
            step: AnimationSamples<Value.AnimatableData>.step,
            limit: AnimationSamples<Value.AnimatableData>.limit,
            environment: environment
        )
        // A round is described from the animation's second value on; see `valuesAhead`.
        let elapsed = animatorState.evaluatedElapsed
            + (ahead?.repeats == true ? AnimationSamples<Value.AnimatableData>.step : 0)
        described = (animatorState.generation, target, ahead != nil, elapsed)
        // An animation made while an event is handled, outside a frame, has not been
        // evaluated yet: its clock starts at the frame that follows, and the time here is
        // still the last frame's. The time is put right at that frame, above, before
        // anything reads it.
        let time = animatorState.startTime.map { $0 + elapsed } ?? time
        samplesBox.samples = ahead.map { ahead in
            AnimationSamples(
                seed: AnimationSamples<Value.AnimatableData>.makeSeed(),
                time: time,
                step: AnimationSamples<Value.AnimatableData>.step,
                values: ahead.values,
                repeats: ahead.repeats
            )
        }
    }

    package mutating func update(
        value: inout (value: Value, changed: Bool),
        defaultAnimation: Animation?,
        environment: Attribute<EnvironmentValues>
    ) {
        update(
            value: &value,
            defaultAnimation: defaultAnimation,
            environment: environment
        ) { _, _ in
            _openSwiftUIEmptyStub()
        }
    }

    package mutating func checkReset() -> Bool {
        guard phase.resetSeed != resetSeed else {
            return false
        }
        reset()
        return true
    }

    package mutating func reset() {
        removeListeners()
        animatorState = nil
        previousModelData = nil
        resetSeed = phase.resetSeed
        samplesBox?.isAnimating = false
        samplesBox?.samples = nil
        described = nil
    }

    package mutating func removeListeners() {
        animatorState?.removeListeners()
    }
}

// MARK: - AnimatorState

final package class AnimatorState<V> where V: VectorArithmetic {
    private var animation: Animation

    private var state: AnimationState<V> = .init()

    private var interval: V = .zero

    private var beginTime: Time

    private var quantizedFrameInterval: Double

    private var nextTime: Time = .zero

    private var previousAnimationValue: V = .zero

    /// Changes whenever the animation changes course.
    package private(set) var generation: UInt32 = 0

    /// How far into the animation it was last evaluated.
    package private(set) var evaluatedElapsed: Double = 0

    /// When the animation's clock started. Nil until it is first evaluated.
    package var startTime: Time? {
        phase == .pending ? nil : beginTime
    }

    private var reason: UInt32? = nil

    private enum Phase {
        case pending
        case first
        case second
        case running
    }

    private var phase: Phase = .pending

    private var listeners: [AnimationListener] = []

    private var logicalListeners: [AnimationListener] = []

    private var isLogicallyComplete: Bool = false

    private struct Fork {
        var animation: Animation
        var state: AnimationState<V>
        var interval: V
        var listeners: [AnimationListener]

        func update(time: Double, environment: Attribute<EnvironmentValues>?) -> Bool {
            var context = AnimationContext(state: state, environment: environment, isLogicallyComplete: false)
            let animtedValue = animation.animate(value: interval, time: time, context: &context)
            return animtedValue == nil || context.isLogicallyComplete
        }
    }

    private var forks: [Fork] = []

    init(
        animation: Animation,
        interval: V,
        at time: Time,
        in transaction: Transaction
    ) {
        self.animation = animation
        self.interval = interval
        self.beginTime = time
        self.nextTime = time
        if let animationFrameInterval = transaction.animationFrameInterval {
            self.quantizedFrameInterval = if animationFrameInterval <= .zero {
                .zero
            } else {
                exp2(floor(log2(animationFrameInterval * 240.0) + 0.01)) / 240.0
            }
            if quantizedFrameInterval < 1.0 / 60.0 {
                self.reason = transaction.animationReason
            } else {
                self.reason = nil
            }
        } else {
            self.quantizedFrameInterval = .zero
            self.reason = nil
        }
    }

    package func updateListeners(
        isLogicallyComplete: Bool,
        time: TimeInterval,
        environment: Attribute<EnvironmentValues>?
    ) {
        if !self.isLogicallyComplete, isLogicallyComplete {
            self.isLogicallyComplete = true
            logicalListeners.forEach { $0.animationWasRemoved() }
            logicalListeners = []
        }
        if !forks.isEmpty {
            var set = IndexSet()
            for index in forks.indices {
                guard forks[index].update(time: time, environment: environment) else {
                    continue
                }
                forks[index].listeners.forEach { $0.animationWasRemoved() }
                set.insert(index)
            }
            forks.remove(atOffsets: set)
        }
    }

    package func removeListeners() {
        listeners.forEach { $0.animationWasRemoved() }
        listeners = []
        logicalListeners.forEach { $0.animationWasRemoved() }
        logicalListeners = []
    }

    package func forkListeners(
        animation: Animation,
        state: AnimationState<V>,
        interval: V
    ) {
        guard !isLogicallyComplete, !logicalListeners.isEmpty else {
            return
        }
        let fork = Fork(
            animation: animation,
            state: state,
            interval: interval,
            listeners: logicalListeners
        )
        forks.append(fork)
    }

    package func combine(
        newAnimation: Animation,
        newInterval: V,
        at time: Time,
        in transaction: Transaction,
        environment: Attribute<EnvironmentValues>?
    ) {
        generation &+= 1
        if phase == .pending, !Semantics.MergeCoincidentAnimations.isEnabled {
            animation = newAnimation
            interval = newInterval
        } else {
            let elapsed = time - beginTime
            // The animation is not evaluated again in this update, and a description made
            // now has to start from now.
            evaluatedElapsed = elapsed
            var context = AnimationContext(
                state: state,
                environment: environment,
                isLogicallyComplete: isLogicallyComplete
            )
            forkListeners(animation: animation, state: state, interval: interval)
            isLogicallyComplete = false
            if newAnimation.shouldMerge(
                previous: animation,
                value: interval,
                time: elapsed,
                context: &context
            ) {
                state = context.state
                animation = newAnimation
            } else {
                combineAnimation(
                    into: &animation,
                    state: &state,
                    value: interval,
                    elapsed: elapsed,
                    newAnimation: newAnimation,
                    newValue: newInterval
                )
            }
            interval += newInterval
            nextTime = time
        }
        if let animationFrameInterval = transaction.animationFrameInterval {
            let newQuantizedFrameInterval: Double = if animationFrameInterval <= .zero {
                .zero
            } else {
                exp2(floor(log2(animationFrameInterval * 240.0) + 0.01)) / 240.0
            }
            quantizedFrameInterval = min(
                newQuantizedFrameInterval,
                quantizedFrameInterval
            )
            if quantizedFrameInterval < 1.0 / 60.0 {
                self.reason = transaction.animationReason
            } else {
                self.reason = nil
            }
        }
    }

    package func update(
        _ value: inout V,
        at time: Time,
        environment: Attribute<EnvironmentValues>?
    ) -> Bool {
        guard time > nextTime + quantizedFrameInterval * -0.5 else {
            value += previousAnimationValue
            value -= interval
            return false
        }
        switch phase {
        case .pending:
            beginTime = time
            phase = .first
        case .first:
            phase = .second
            guard CoreGlue.shared.hasTestHost() else {
                nextTime += time - beginTime
                beginTime = time
                value += previousAnimationValue
                value -= interval
                return false
            }
        case .second:
            let doubleInterval = max(quantizedFrameInterval, 1.0 / 60.0) + quantizedFrameInterval
            if doubleInterval < time - beginTime {
                if !CoreGlue.shared.hasTestHost() {
                    beginTime = time - doubleInterval
                }
            }
            phase = .running
        case .running:
            break
        }
        let elapsed = time - beginTime
        evaluatedElapsed = elapsed
        var context = AnimationContext(
            state: state,
            environment: environment,
            isLogicallyComplete: isLogicallyComplete
        )
        guard let newValue = animation.animate(
            value: interval,
            time: elapsed,
            context: &context
        ) else {
            return true
        }
        updateListeners(
            isLogicallyComplete: context.isLogicallyComplete,
            time: elapsed,
            environment: environment
        )
        state = context.state
        value += newValue
        value -= interval
        previousAnimationValue = newValue
        nextTime = time
        if quantizedFrameInterval > .zero {
            nextTime = Time(seconds: (floor(time.seconds / quantizedFrameInterval) + 1.0) * quantizedFrameInterval)
        }
        return false
    }

    /// The values the animation will take from where it was last evaluated, `step` seconds
    /// apart. Either they end with `target`, the value it is heading for, or the animation
    /// repeats for ever and they are one round of it, ending as it begins. Nil when it
    /// neither ends nor comes round again within `limit` values. Nothing about the animation
    /// changes.
    package func valuesAhead(
        target: V,
        step: Double,
        limit: Int,
        environment: Attribute<EnvironmentValues>?
    ) -> (values: [V], repeats: Bool)? {
        var context = AnimationContext(
            state: state,
            environment: environment,
            isLogicallyComplete: isLogicallyComplete
        )
        var values: [V] = []
        // The values at which an animation that repeats started again.
        var restarts: [Int] = []
        var repeatIndex = context.repeatIndex
        for index in 0 ..< limit {
            guard let animated = animation.animate(
                value: interval,
                time: evaluatedElapsed + Double(index) * step,
                context: &context
            ) else {
                values.append(target)
                return (values, false)
            }
            var value = target
            value += animated
            value -= interval
            values.append(value)
            if context.repeatIndex != repeatIndex {
                repeatIndex = context.repeatIndex
                restarts.append(index)
            }
        }
        // It has not ended. One that repeats starts again at every frame its base ends at,
        // so, a fixed step apart, its values come round exactly: after one run when every
        // run goes the same way, after two when they go there and back. The round is taken
        // from the second value on. The very first value of an animation that runs the same
        // way every time is its start, and never comes again: at the frame a run ends the
        // value is the end, and the frame after is already a step into the next run.
        for later in restarts.dropFirst().prefix(2) {
            let period = later - restarts[0]
            guard period > 0, 2 * period + 1 < values.count else {
                break
            }
            let comesRound = (1 ... period).allSatisfy { index in
                var difference = values[index + period]
                difference -= values[index]
                return difference.magnitudeSquared < 1e-6
            }
            if comesRound {
                return (Array(values[1 ... period + 1]), true)
            }
        }
        return nil
    }

    package func nextUpdate() {
        CoreGlue.shared.nextUpdate(
            nextTime: nextTime,
            interval: quantizedFrameInterval,
            reason: reason
        )
    }

    package func addListeners(transaction: Transaction) {
        if let listener = transaction.animationListener {
            listeners.append(listener)
            listener.animationWasAdded()
        }
        if let logicalListener = transaction.animationLogicalListener {
            logicalListener.animationWasAdded()
            if isLogicallyComplete {
                logicalListener.animationWasRemoved()
            } else {
                logicalListeners.append(logicalListener)
            }
        }
    }
}

// MARK: - FrameVelocityFilter

private struct FrameVelocityFilter {
    var currentVelocity: Double?
    var previous: ((Time, CGRect.AnimatableData))?

    mutating func addSample(_ rect: CGRect.AnimatableData, time: Time) {
        guard let (previousTime, previousRect) = previous,
              previousTime <= time else {
            previous = (time, rect)
            return
        }
        let deltaX = rect.first.first - previousRect.first.first
        let deltaY = rect.first.second - previousRect.first.second
        let deltaWidth = rect.second.first - previousRect.second.first
        let deltaHeight = rect.second.second - previousRect.second.second

        let timeFactor = 1.0 / (time - previousTime)

        let velocityX = timeFactor * deltaX
        let velocityY = timeFactor * deltaY
        let velocityWidth = timeFactor * deltaWidth
        let velocityHeight = timeFactor * deltaHeight

        let velocityRect = CGRect(x: velocityX, y: velocityY, width: velocityWidth, height: velocityHeight)
        let newVelocity = max(abs(velocityRect.minX), abs(velocityRect.maxX), abs(velocityRect.minY), abs(velocityRect.maxY))
        if let existingVelocity = currentVelocity {
            currentVelocity = mix(existingVelocity, newVelocity, by: 0.35)
        } else {
            currentVelocity = newVelocity
        }
        previous = (time, rect)
    }
}
