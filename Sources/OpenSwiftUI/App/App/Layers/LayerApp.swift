//
//  LayerApp.swift
//  OpenSwiftUI
//
//  Shows an `App` through a layer compositor instead of a window of its own. The app draws
//  nothing: each display list becomes a tree of layers (LayerTreeBuilder) that the compositor
//  process draws. The compositor also supplies the screen's size, the frame pacing and the
//  touches.
//
//  Scrolling is the compositor's: a scroll view's viewport becomes a scroll layer that the
//  compositor moves under a touch by itself (CompositorScrolling.swift). So are the
//  animations the engine can describe ahead of time (AnimationSamples.swift): where an item
//  is and how opaque it is. Everything else that changes over time is still evaluated here,
//  frame by frame, and stops while the app is busy.
//
//  OPENSWIFTUI_LAYER_ANIMATIONS=app keeps every animation in the app, to compare.

#if OPENSWIFTUI_LAYERS
import COpenSwiftUIGTKHost
import Foundation
import LayerKit
@_spi(ForOpenSwiftUIOnly) import OpenSwiftUICore

/// Connects to the layer compositor. False when none is listening, or when one accepts
/// the connection and then says nothing.
func connectToLayerCompositor() -> Bool {
    do {
        try LayerHost.shared.connect(name: ProcessInfo.processInfo.processName)
        return true
    } catch {
        return false
    }
}

/// Runs the scene `item` on the compositor `connectToLayerCompositor` reached.
func runLayerApp(_ item: SceneList.Item) -> Never {
    let layerHost = LayerHost.shared
    let screen = layerHost.size
    var environment = item.environment
    environment.compositorScrolls = true
    AnimationDescriptions.areWanted = ProcessInfo.processInfo.environment["OPENSWIFTUI_LAYER_ANIMATIONS"] != "app"
    let host = GTKHostingView(rootView: item.value.view, environment: environment)
    host.resize(width: Int(screen.width), height: Int(screen.height), scale: Double(layerHost.scale))

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let root = CALayer()
    root.anchorPoint = .zero
    root.bounds = CGRect(origin: .zero, size: screen)
    // What a window's background would be.
    root.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    layerHost.rootLayer = root
    CATransaction.commit()

    // Without its compositor the app shows nothing and hears nothing; like an app whose
    // window was closed, it is over.
    layerHost.onDisconnect = {
        FileHandle.standardError.write(Data("OpenSwiftUI: the layer compositor went away\n".utf8))
        exit(0)
    }
    let session = LayerSession(host: host, builder: LayerTreeBuilder(root: root, scale: layerHost.scale))
    session.start()
    layerHost.run()
}

private final class LayerSession {
    private let host: GTKHostingView
    private let builder: LayerTreeBuilder
    private var link: CADisplayLink?
    /// The graph's clock never runs backwards, though a touch can be handled a moment
    /// after the time of the frame that follows it.
    private var clock = 0.0
    /// When a frame that arrived late was last made up for.
    private var lastCatchUp = 0.0
    /// Counts the times the link was put to sleep until an update is due, so that a
    /// wake-up set for an earlier sleep does nothing.
    private var sleeps = 0

    init(host: GTKHostingView, builder: LayerTreeBuilder) {
        self.host = host
        self.builder = builder
    }

    func start() {
        // The compositor says when each frame is drawn; the link sleeps while nothing here
        // needs another frame.
        let link = CADisplayLink { [unowned self] link in
            let now = CACurrentMediaTime()
            guard now - link.timestamp > 2 * link.duration else {
                self.tick(time: link.timestamp)
                return
            }
            // The main thread was busy, and the frames it missed now arrive all at once.
            // They are one late frame, not many, and it is drawn for now.
            if now - self.lastCatchUp > link.duration {
                self.lastCatchUp = now
                self.tick(time: now)
            }
        }
        link.add(to: .main, forMode: .common)
        self.link = link
        host.updateRequested = { [weak self] in
            // The graph may ask from any thread, and for a time that is still far off.
            DispatchQueue.main.async { self?.sleepUntilNextUpdate() }
        }
        LayerHost.shared.onTouch = { [unowned self] touch in
            self.touch(touch)
        }
        tick(time: CACurrentMediaTime())
    }

    private func tick(time: Double) {
        clock = max(clock, time)
        // State changes are committed by a run-loop observer when the loop goes idle;
        // committing here shows this frame's input in this frame.
        RunLoop.flushObservers()
        _ = host.tick(time: clock)
        if let displayList = host.takeDisplayList() {
            builder.update(displayList, time: host.currentTimestamp)
        }
        sleepUntilNextUpdate()
    }

    /// Frames are asked for only while the next update is at most a frame or two away. For
    /// one further off, such as an animation that starts after a delay, the link sleeps
    /// and a timer wakes it in time.
    private func sleepUntilNextUpdate() {
        guard let link else { return }
        guard let deadline = host.updateDeadline else {
            link.isPaused = true
            return
        }
        let frame = link.duration > 0 ? link.duration : 1.0 / 60.0
        // From now, not from the last frame: the timer below counts from now.
        let wait = deadline - CACurrentMediaTime()
        guard wait > 2 * frame else {
            link.isPaused = false
            return
        }
        link.isPaused = true
        sleeps += 1
        let sleep = sleeps
        DispatchQueue.main.asyncAfter(deadline: .now() + wait - frame) { [weak self] in
            guard let self, self.sleeps == sleep else { return }
            self.link?.isPaused = false
        }
    }

    private func touch(_ touch: LayerTouch) {
        let phase: OSUIPointerPhase = switch touch.phase {
        case .began: OSUI_POINTER_BEGAN
        case .moved: OSUI_POINTER_MOVED
        case .ended: OSUI_POINTER_ENDED
        case .cancelled: OSUI_POINTER_CANCELLED
        }
        host.pointer(phase: phase, location: touch.location, timestamp: Time(seconds: touch.timestamp))
        // Answer the touch now rather than at the next frame.
        tick(time: CACurrentMediaTime())
    }
}
#endif
