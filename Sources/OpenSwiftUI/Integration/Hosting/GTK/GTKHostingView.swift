//
//  GTKHostingView.swift
//  OpenSwiftUI
//
//  Hosts one OpenSwiftUI view graph in a GTK4 window: the Linux counterpart of
//  UIHostingView. Modelled on upstream's experimental SDLHostingView.

#if OPENSWIFTUI_GTK
import CGtk
import COpenSwiftUIGTKHost
import Foundation
@_spi(ForOpenSwiftUIOnly) import OpenSwiftUICore

final class GTKHostingView: ViewRendererHost, ViewGraphRenderHost, EventGraphHost, EventBindingManagerDelegate {
    typealias RootView = ModifiedContent<AnyView, HitTestBindingModifier>

    let viewGraph: ViewGraph
    let eventBindingManager = EventBindingManager()
    var focusedResponder: ResponderNode? { nil }
    let rootView: AnyView
    var environment: EnvironmentValues
    var size: CGSize = .zero
    var scale: CGFloat = 1
    var currentTimestamp: Time = .zero
    var propertiesNeedingUpdate: ViewRendererHostProperties = .all
    var renderingPhase: ViewRenderingPhase = .none
    var externalUpdateCount: Int = 0

    private var displayList = DisplayList()
    private var needsDisplay = true
    /// Latest frame-clock time, in seconds.
    private var clock = 0.0
    private var lastRenderClock: Double?
    private let deadlineLock = NSLock()
    /// Frame-clock time at which the graph has to be evaluated again.
    private var deadline = 0.0

    private var pointerSerial = 0
    private var pointerDown = false

    init(rootView: AnyView, environment: EnvironmentValues) {
        self.rootView = rootView
        self.environment = environment
        viewGraph = ViewGraph(
            rootViewType: RootView.self,
            requestedOutputs: [.displayList, .layout, .viewResponders]
        )
        initializeViewGraph()
        eventBindingManager.host = self
        eventBindingManager.delegate = self
    }

    // MARK: Window callbacks

    func resize(width: Int, height: Int, scale: Double) {
        size = CGSize(width: width, height: height)
        self.scale = CGFloat(scale)
        environment.displayScale = CGFloat(scale)
        Update.ensure { invalidateProperties([.size, .containerSize, .environment]) }
        requestUpdate(after: 0)
    }

    /// Advances the graph to `time`. Returns whether the window has to be repainted.
    func tick(time: Double) -> Bool {
        clock = time
        renderIfNeeded()
        return needsDisplay
    }

    func draw(_ cr: OpaquePointer) {
        // A resize arrives between ticks; lay out for the new size before painting it.
        renderIfNeeded()
        needsDisplay = false
        var renderer = CairoDisplayListRenderer(cr: cr)
        renderer.clear(size: size)
        renderer.draw(displayList)
    }

    func pointer(phase: OSUIPointerPhase, location: CGPoint) {
        let eventPhase: EventPhase
        switch phase {
        case OSUI_POINTER_BEGAN:
            guard !pointerDown else { return }
            Update.ensure { eventBindingManager.reset() }
            pointerDown = true
            pointerSerial &+= 1
            eventPhase = .began
        case OSUI_POINTER_MOVED:
            guard pointerDown else { return }
            eventPhase = .active
        case OSUI_POINTER_ENDED:
            guard pointerDown else { return }
            pointerDown = false
            eventPhase = .ended
        default:
            guard pointerDown else { return }
            pointerDown = false
            eventPhase = .failed
        }
        // The responder tree hit-tests against the layout of the last evaluated graph.
        renderIfNeeded()
        let event = MouseEvent(
            timestamp: .systemUptime,
            button: .primary,
            phase: eventPhase,
            location: location,
            globalLocation: location,
            modifiers: []
        )
        eventBindingManager.send(event, id: pointerSerial)
    }

    private func renderIfNeeded() {
        let due = deadlineLock.withLock {
            guard clock >= deadline else { return false }
            deadline = .infinity
            return true
        }
        guard due, size.width > 0, size.height > 0 else { return }
        render(interval: max(clock - (lastRenderClock ?? clock), 0), targetTimestamp: nil)
        lastRenderClock = clock
    }

    // MARK: ViewRendererHost

    func requestUpdate(after delay: Double) {
        deadlineLock.withLock {
            deadline = min(deadline, clock + max(delay, 0))
        }
    }

    func updateRootView() { viewGraph.setRootView(Self.makeRootView(rootView)) }
    func updateEnvironment() { viewGraph.setEnvironment(environment) }
    func updateSize() { viewGraph.setProposedSize(size) }
    func updateSafeArea() { _ = viewGraph.setSafeAreaInsets(EdgeInsets()) }
    func updateContainerSize() { viewGraph.setContainerSize(.fixed(size)) }
    func updateFocusStore() {}
    func updateFocusedItem() {}
    func updateFocusedValues() {}
    func updateAccessibilityEnvironment() {}

    func `as`<T>(_ type: T.Type) -> T? {
        self as? T
    }

    // MARK: ViewGraphRenderHost

    func renderDisplayList(
        _ displayList: DisplayList,
        asynchronous: Bool,
        time: Time,
        nextTime: Time,
        targetTimestamp: Time?,
        version: DisplayList.Version,
        maxVersion: DisplayList.Version
    ) -> Time {
        precondition(!asynchronous, "GTK presentation is main-thread only")
        if ProcessInfo.processInfo.environment["OPENSWIFTUI_PRINT_TREE"] == "1" {
            print("DisplayList at \(time):\n\(displayList.description)")
        }
        self.displayList = displayList
        needsDisplay = true
        return nextTime
    }

    // MARK: EventBindingManagerDelegate

    func didUpdate(phase: GesturePhase<Void>, in eventBindingManager: EventBindingManager) {
        if phase.isTerminal { eventBindingManager.reset() }
    }
}
#endif
