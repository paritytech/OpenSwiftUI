//
//  GTKApp.swift
//  OpenSwiftUI
//
//  Launches an `App` in a GTK4 window: the Linux counterpart of the UIKit/AppKit app delegates.
//
//  Set `OPENSWIFTUI_GTK_CAPTURE_DIR` to render offscreen instead: frames are written there as
//  PNGs on a virtual clock (`OPENSWIFTUI_GTK_CAPTURE_FRAMES`, default 60, at
//  `OPENSWIFTUI_GTK_CAPTURE_FPS`, default 30). `OPENSWIFTUI_GTK_CAPTURE_TAPS` scripts taps as
//  `frame:x,y;frame:x,y` in logical points.

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
        taps: scriptedTaps(from: environment["OPENSWIFTUI_GTK_CAPTURE_TAPS"])
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

private func scriptedTaps(from description: String?) -> [Int: CGPoint] {
    var taps: [Int: CGPoint] = [:]
    for entry in (description ?? "").split(separator: ";") {
        let parts = entry.split(whereSeparator: { $0 == ":" || $0 == "," })
        guard parts.count == 3, let frame = Int(parts[0]), let x = Double(parts[1]), let y = Double(parts[2]) else {
            fatalError("OPENSWIFTUI_GTK_CAPTURE_TAPS: expected frame:x,y, got \(entry)")
        }
        taps[frame] = CGPoint(x: x, y: y)
    }
    return taps
}

private func withOptionalCString<Result>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> Result) -> Result {
    guard let string else { return body(nil) }
    return string.withCString(body)
}

private final class GTKSession {
    let host: GTKHostingView
    private let taps: [Int: CGPoint]
    private var frame = 0

    init(host: GTKHostingView, taps: [Int: CGPoint]) {
        self.host = host
        self.taps = taps
    }

    static func from(_ context: UnsafeMutableRawPointer?) -> GTKSession {
        Unmanaged<GTKSession>.fromOpaque(context!).takeUnretainedValue()
    }

    func tick(time: Double) -> Bool {
        defer { frame += 1 }
        let needsDisplay = host.tick(time: time)
        guard let location = taps[frame] else { return needsDisplay }
        host.pointer(phase: OSUI_POINTER_BEGAN, location: location)
        host.pointer(phase: OSUI_POINTER_ENDED, location: location)
        return true
    }
}
#endif
