//
//  Toolbar.swift
//  SwiftUI
//
//  `toolbar` items for the bars a NavigationStack draws. Items travel to the stack as a
//  preference of the screen that declares them.
//
//  Not implemented: `toolbar(_:for:)` visibility, customizable toolbars (`toolbar(id:)`),
//  `ToolbarTitleMenu`, and the keyboard, status and secondary-action placements, whose items
//  are not shown.

import Foundation
public import OpenSwiftUI

// MARK: - Placement

/// A structure that defines the placement of a toolbar item.
public struct ToolbarItemPlacement: Hashable, Sendable {
    enum Slot: Hashable, Sendable {
        case leading, principal, trailing, bottom, unsupported
    }

    private var name: String
    var slot: Slot

    private init(_ name: String, _ slot: Slot) {
        self.name = name
        self.slot = slot
    }

    public static let automatic = ToolbarItemPlacement("automatic", .trailing)
    public static let principal = ToolbarItemPlacement("principal", .principal)
    public static let navigation = ToolbarItemPlacement("navigation", .leading)
    public static let primaryAction = ToolbarItemPlacement("primaryAction", .trailing)
    public static let secondaryAction = ToolbarItemPlacement("secondaryAction", .unsupported)
    public static let status = ToolbarItemPlacement("status", .unsupported)
    public static let confirmationAction = ToolbarItemPlacement("confirmationAction", .trailing)
    public static let cancellationAction = ToolbarItemPlacement("cancellationAction", .leading)
    public static let destructiveAction = ToolbarItemPlacement("destructiveAction", .trailing)
    public static let keyboard = ToolbarItemPlacement("keyboard", .unsupported)
    public static let topBarLeading = ToolbarItemPlacement("topBarLeading", .leading)
    public static let topBarTrailing = ToolbarItemPlacement("topBarTrailing", .trailing)
    public static let navigationBarLeading = ToolbarItemPlacement("navigationBarLeading", .leading)
    public static let navigationBarTrailing = ToolbarItemPlacement("navigationBarTrailing", .trailing)
    public static let bottomBar = ToolbarItemPlacement("bottomBar", .bottom)
}

// MARK: - Content

/// Conforming types represent items that can be placed in various locations in a toolbar.
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent

    @ToolbarContentBuilder var body: Body { get }
}

/// One item as the stack shows it.
struct ToolbarEntry: Equatable {
    var placement: ToolbarItemPlacement
    var view: AnyView
    /// Views cannot be compared, so each evaluation of a toolbar gets a new stamp and counts
    /// as a change.
    var stamp: Int

    static func == (lhs: ToolbarEntry, rhs: ToolbarEntry) -> Bool {
        lhs.stamp == rhs.stamp && lhs.placement == rhs.placement
    }
}

/// Toolbar content that is items itself rather than a composition with a `body`.
private protocol ToolbarEntrySource {
    func entries(stamp: Int) -> [ToolbarEntry]
}

private func toolbarEntries<C>(of content: C, stamp: Int) -> [ToolbarEntry] where C: ToolbarContent {
    if let source = content as? any ToolbarEntrySource {
        return source.entries(stamp: stamp)
    }
    return toolbarEntries(of: content.body, stamp: stamp)
}

/// A model that represents an item which can be placed in the toolbar or navigation bar.
public struct ToolbarItem<ID, Content>: ToolbarContent, ToolbarEntrySource where Content: View {
    private var placement: ToolbarItemPlacement
    private var content: Content

    // `return` keeps the toolbar builder from wrapping the item.
    public var body: ToolbarItem { return self }

    fileprivate func entries(stamp: Int) -> [ToolbarEntry] {
        [ToolbarEntry(placement: placement, view: AnyView(content), stamp: stamp)]
    }
}

extension ToolbarItem where ID == () {
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
}

/// A model that represents a group of toolbar items which can be placed in the toolbar or
/// navigation bar.
public struct ToolbarItemGroup<Content>: ToolbarContent, ToolbarEntrySource where Content: View {
    private var placement: ToolbarItemPlacement
    private var content: Content

    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    public var body: ToolbarItemGroup { return self }

    fileprivate func entries(stamp: Int) -> [ToolbarEntry] {
        [ToolbarEntry(placement: placement, view: AnyView(HStack(spacing: toolbarItemSpacing) { content }), stamp: stamp)]
    }
}

/// The result of a toolbar builder: its items in order.
public struct ToolbarContentList: ToolbarContent, ToolbarEntrySource {
    fileprivate var children: [any ToolbarContent]

    public var body: ToolbarContentList { return self }

    fileprivate func entries(stamp: Int) -> [ToolbarEntry] {
        children.flatMap { toolbarEntries(of: $0, stamp: stamp) }
    }
}

/// Constructs a toolbar item set from multi-expression closures.
@resultBuilder
public struct ToolbarContentBuilder {
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: ToolbarContent {
        content
    }

    public static func buildBlock<each Content>(_ content: repeat each Content) -> ToolbarContentList
    where repeat each Content: ToolbarContent {
        var children: [any ToolbarContent] = []
        for child in repeat each content {
            children.append(child)
        }
        return ToolbarContentList(children: children)
    }

    public static func buildOptional(_ content: ToolbarContentList?) -> ToolbarContentList {
        content ?? ToolbarContentList(children: [])
    }

    public static func buildEither(first content: ToolbarContentList) -> ToolbarContentList {
        content
    }

    public static func buildEither(second content: ToolbarContentList) -> ToolbarContentList {
        content
    }

    public static func buildLimitedAvailability(_ content: ToolbarContentList) -> ToolbarContentList {
        content
    }
}

// MARK: - View modifiers

let toolbarItemSpacing: CGFloat = 16

struct NavigationToolbarKey: PreferenceKey {
    static var defaultValue: [ToolbarEntry] { [] }

    static func reduce(value: inout [ToolbarEntry], nextValue: () -> [ToolbarEntry]) {
        value.append(contentsOf: nextValue())
    }
}

private nonisolated(unsafe) var lastToolbarStamp = 0

extension View {
    /// Populates the toolbar or navigation bar with the specified items.
    public func toolbar<Content>(@ToolbarContentBuilder content: () -> Content) -> some View where Content: ToolbarContent {
        lastToolbarStamp += 1
        let entries = toolbarEntries(of: content(), stamp: lastToolbarStamp)
        return transformPreference(NavigationToolbarKey.self) { $0.append(contentsOf: entries) }
    }

    /// Populates the toolbar or navigation bar with the views you provide.
    public func toolbar<Content>(@ViewBuilder content: () -> Content) -> some View where Content: View {
        toolbar {
            ToolbarItemGroup(placement: .automatic, content: content)
        }
    }
}
