//
//  CompositorScrolling.swift
//  OpenSwiftUI
//
//  What lets a scroll view leave its scrolling to the host. A host whose compositor can move
//  content under a touch by itself says so in the environment. A scroll view then stops
//  handling drags, marks its viewport with `CompositorScrollEffect`, and keeps its own offset
//  in step with what the host reports, so that layout and hit testing still know where the
//  content is. The mark travels in the display list as a platform group.

package import Foundation
package import OpenSwiftUICore

/// Shared by one scroll view and the host that scrolls for it.
package final class CompositorScrollHandle {
    /// The scroll view's part: it is told where the content is and whether it is at rest.
    /// Called on the main thread.
    package var moved: ((_ offset: CGSize, _ isAtRest: Bool) -> Void)?

    /// The longest the scroll view goes without hearing of content that is moving.
    private static let interval = 0.1
    private var lastTold = 0.0
    private var untold: CGSize?
    private var isWaiting = false

    package init() {}

    /// The host's part: the compositor has moved the content, to be called on the main
    /// thread. The scroll view wants the offset for layout and hit testing, not to draw, so
    /// while the content moves it hears of it ten times a second and not every frame; it
    /// hears at once of content that has come to rest.
    package func report(_ offset: CGSize, isAtRest: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !isAtRest, now - lastTold < Self.interval else {
            untold = nil
            lastTold = now
            moved?(offset, isAtRest)
            return
        }
        untold = offset
        guard !isWaiting else { return }
        isWaiting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.interval - (now - lastTold)) { [weak self] in
            guard let self else { return }
            self.isWaiting = false
            if let offset = self.untold {
                self.untold = nil
                self.lastTold = ProcessInfo.processInfo.systemUptime
                self.moved?(offset, false)
            }
        }
    }
}

/// Marks a scroll view's viewport. The views inside are placed from the viewport's corner.
package struct CompositorScrollEffect: RendererEffect {
    package var handle: CompositorScrollHandle
    /// The size of what scrolls.
    package var contentSize: CGSize
    package var axes: Axis.Set

    package init(handle: CompositorScrollHandle, contentSize: CGSize, axes: Axis.Set) {
        self.handle = handle
        self.contentSize = contentSize
        self.axes = axes
    }

    package static var isolatesChildPosition: Bool { true }

    /// The viewport stays in the display list while there is nothing in it: its layer, and
    /// with it where the compositor has scrolled to, is kept for when there is again.
    package static var preservesEmptyContent: Bool { true }

    package func effectValue(size: CGSize) -> DisplayList.Effect {
        .platformGroup(CompositorScrollGroup(handle: handle, contentSize: contentSize, axes: axes))
    }
}

/// Marks what scrolls inside a viewport marked with `CompositorScrollEffect`. The scroll view
/// still lays it out scrolled, for layout and hit testing; where it is on screen is the
/// host's business, so the host ignores the position this group has in the display list.
package struct CompositorScrollContentEffect: RendererEffect {
    package init() {}

    package static var isolatesChildPosition: Bool { true }

    package func effectValue(size: CGSize) -> DisplayList.Effect {
        .platformGroup(CompositorScrollContent())
    }
}

/// A scroll view's viewport in the display list. A host that does not scroll by itself draws
/// what is inside and is done.
package final class CompositorScrollGroup: CompositorGroup {
    package let handle: CompositorScrollHandle
    package let contentSize: CGSize
    package let axes: Axis.Set

    init(handle: CompositorScrollHandle, contentSize: CGSize, axes: Axis.Set) {
        self.handle = handle
        self.contentSize = contentSize
        self.axes = axes
    }
}

/// What scrolls, in the display list.
package final class CompositorScrollContent: CompositorGroup {}

/// A group that is only a mark for the host: there is no platform view behind it.
package class CompositorGroup: PlatformGroupFactory {
    package var viewType: any Any.Type { Self.self }

    package func makePlatformGroup() -> AnyObject? { nil }
    package func needsUpdateFor(newValue: any PlatformGroupFactory) -> Bool { true }
    package func updatePlatformGroup(_ view: inout AnyObject) {}
    package func platformGroupContainer(_ view: AnyObject) -> AnyObject { view }
}

private struct CompositorScrollsKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// The host scrolls content under a touch by itself; see `CompositorScrollEffect`.
    package var compositorScrolls: Bool {
        get { self[CompositorScrollsKey.self] }
        set { self[CompositorScrollsKey.self] = newValue }
    }
}
