//
//  GTKApp.swift
//  OpenSwiftUI
//
//  Launches an `App` in a GTK4 window: the Linux counterpart of the UIKit/AppKit app delegates.
//
//  Set `OPENSWIFTUI_GTK_CAPTURE_DIR` to render offscreen instead: frames are written there as
//  PNGs on a virtual clock (`OPENSWIFTUI_GTK_CAPTURE_FRAMES`, default 60, at
//  `OPENSWIFTUI_GTK_CAPTURE_FPS`, default 30). `OPENSWIFTUI_GTK_CAPTURE_POINTER` scripts the
//  pointer as `frame:down:x,y;frame:move:x,y;frame:up:x,y` in logical points; the events are
//  stamped with the virtual clock, so drag velocities come out as they would at that frame rate.

#if OPENSWIFTUI_GTK
import COpenSwiftUIGTKHost
import Foundation
import OpenCoreGraphicsShims
@_spi(ForOpenSwiftUIOnly) import OpenSwiftUICore

/// A phone-shaped default for scenes that do not declare a size.
private let defaultWindowSize = CGSize(width: 390, height: 780)

func runGTKApp(_ app: some App) -> Never {
    PangoTextLayout.install()
    let graph = AppGraph(app: app)
    let item: SceneList.Item? = Update.ensure {
        graph.instantiate()
        AppGraph.shared = graph
        return graph.rootSceneList?.items.first
    }
    guard let item else {
        print("OpenSwiftUI: the app declares no scene to show")
        exit(1)
    }
    let processInfo = ProcessInfo.processInfo
    let environment = processInfo.environment
    let session = GTKSession(
        host: GTKHostingView(rootView: item.value.view, environment: item.environment),
        script: scriptedPointer(from: environment["OPENSWIFTUI_GTK_CAPTURE_POINTER"])
    )
    var callbacks = OSUIGTKHostCallbacks()
    callbacks.resize = { context, width, height, scale in
        GTKSession.from(context).host.resize(width: Int(width), height: Int(height), scale: scale)
    }
    callbacks.tick = { context, time in
        GTKSession.from(context).tick(time: time)
    }
    callbacks.draw = { context, cr, _, _ in
        guard let cr else { return }
        GTKSession.from(context).host.draw(cr)
    }
    callbacks.pointer = { context, phase, x, y, _ in
        GTKSession.from(context).host.pointer(phase: phase, location: CGPoint(x: x, y: y))
    }
    let size = item.defaultSize ?? defaultWindowSize
    let name = processInfo.processName
    let status = name.withCString { title in
        // GApplication ids need at least two dot-separated elements.
        "org.openswiftuiproject.\(name.filter { $0.isLetter || $0.isNumber })".withCString { applicationID in
            withOptionalCString(environment["OPENSWIFTUI_GTK_CAPTURE_DIR"]) { captureDirectory in
                var options = OSUIGTKHostOptions()
                options.application_id = applicationID
                options.title = title
                options.width = Int32(size.width)
                options.height = Int32(size.height)
                options.capture_directory = captureDirectory
                options.capture_frames = environment["OPENSWIFTUI_GTK_CAPTURE_FRAMES"].flatMap(Int32.init) ?? 60
                options.capture_fps = environment["OPENSWIFTUI_GTK_CAPTURE_FPS"].flatMap(Int32.init) ?? 30
                return osui_gtk_host_run(&options, &callbacks, Unmanaged.passUnretained(session).toOpaque())
            }
        }
    }
    exit(status)
}

private struct ScriptedPointerEvent {
    var phase: OSUIPointerPhase
    var location: CGPoint
}

private func scriptedPointer(from description: String?) -> [Int: [ScriptedPointerEvent]] {
    var script: [Int: [ScriptedPointerEvent]] = [:]
    for entry in (description ?? "").split(separator: ";") {
        let parts = entry.split(whereSeparator: { $0 == ":" || $0 == "," })
        let phase: OSUIPointerPhase? = switch parts.count == 4 ? parts[1] : "" {
        case "down": OSUI_POINTER_BEGAN
        case "move": OSUI_POINTER_MOVED
        case "up": OSUI_POINTER_ENDED
        default: nil
        }
        guard let phase, let frame = Int(parts[0]), let x = Double(parts[2]), let y = Double(parts[3]) else {
            fatalError("OPENSWIFTUI_GTK_CAPTURE_POINTER: expected frame:down|move|up:x,y, got \(entry)")
        }
        script[frame, default: []].append(ScriptedPointerEvent(phase: phase, location: CGPoint(x: x, y: y)))
    }
    return script
}

private func withOptionalCString<Result>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> Result) -> Result {
    guard let string else { return body(nil) }
    return string.withCString(body)
}

private final class GTKSession {
    let host: GTKHostingView
    private let script: [Int: [ScriptedPointerEvent]]
    private var frame = 0
    /// Scripted events are stamped from here plus the frame clock.
    private let scriptEpoch = Time.systemUptime

    init(host: GTKHostingView, script: [Int: [ScriptedPointerEvent]]) {
        self.host = host
        self.script = script
    }

    static func from(_ context: UnsafeMutableRawPointer?) -> GTKSession {
        Unmanaged<GTKSession>.fromOpaque(context!).takeUnretainedValue()
    }

    func tick(time: Double) -> Bool {
        defer { frame += 1 }
        // GLib runs the main thread, so nothing else services Foundation's main run loop and
        // the main dispatch queue. OpenSwiftUI posts work to both (timers, deferred actions).
        // One pass without waiting handles whatever is due.
        _ = RunLoop.main.run(mode: .default, before: Date())
        for event in script[frame] ?? [] {
            host.pointer(phase: event.phase, location: event.location, timestamp: scriptEpoch + time)
        }
        // State changes are committed by a run-loop observer that fires when the Foundation
        // run loop goes idle, which it never does under GLib. Committing here, before the
        // frame is evaluated, shows input from this frame in this frame.
        RunLoop.flushObservers()
        return host.tick(time: time)
    }
}
#endif
