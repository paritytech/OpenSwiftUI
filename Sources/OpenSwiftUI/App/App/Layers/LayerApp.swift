//
//  LayerApp.swift
//  OpenSwiftUI
//
//  Shows an `App` through a layer compositor instead of a window of its own. The app draws
//  nothing: each display list becomes a tree of layers (LayerTreeBuilder) that the compositor
//  process draws. The compositor also supplies the screen's size, the frame pacing and the
//  touches.
//
//  Animations are still evaluated here, frame by frame, so a busy app still stutters. What
//  the compositor could run on its own (springs, scrolling) is not handed over yet.

#if OPENSWIFTUI_LAYERS
import COpenSwiftUIGTKHost
import Foundation
import LayerKit
@_spi(ForOpenSwiftUIOnly) import OpenSwiftUICore

/// Connects to the layer compositor. False when none is listening.
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
    let host = GTKHostingView(rootView: item.value.view, environment: item.environment)
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

    init(host: GTKHostingView, builder: LayerTreeBuilder) {
        self.host = host
        self.builder = builder
    }

    func start() {
        // The compositor says when each frame is drawn; the link sleeps while nothing here
        // needs another frame.
        let link = CADisplayLink { [unowned self] link in
            self.tick(time: link.timestamp)
        }
        link.add(to: .main, forMode: .common)
        self.link = link
        host.updateRequested = { [weak link] in
            // The graph may ask from any thread.
            DispatchQueue.main.async { link?.isPaused = false }
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
            builder.update(displayList)
        }
        link?.isPaused = !host.hasPendingUpdate
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
