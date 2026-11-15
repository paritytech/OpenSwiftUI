//
//  NavigationSupport.swift
//  SwiftUI
//
//  What views inside a NavigationStack use to talk to it: links, destinations, titles, dismiss.
//
//  A destination is built by a closure or view that belongs to the view declaring it, and the
//  stack shows it somewhere else. To keep a shown destination current, every evaluation of a
//  declaring view stores its builder again and raises a version number that the stack reads
//  through a preference; the stack then rebuilds the screens above the declaring one. Only
//  those: a declaration made inside a destination can therefore never rebuild the screen it
//  is in, which would loop.

import Foundation
public import OpenSwiftUI

// MARK: - Navigator

/// The stack's side of the conversation, shared through the environment. A reference, so that
/// storing a builder while a view's body runs does not itself change any view state.
final class Navigator {
    /// Destination builders by the type of value they present.
    private var destinations: [ObjectIdentifier: (AnyHashable) -> AnyView] = [:]
    /// The content of screens that were pushed with a view rather than a value.
    private var views: [UUID: AnyView] = [:]
    /// Screens that left the stack last; their content is kept while they animate out.
    private var leaving: [UUID] = []
    /// What to do when a screen pushed with a view leaves the stack.
    private var removalActions: [UUID: () -> Void] = [:]
    private var version = 0

    var push: (AnyHashable) -> Void = { _ in }
    var pushView: (UUID) -> Void = { _ in }
    /// Pops the screen pushed with this view, and everything above it.
    var popView: (UUID) -> Void = { _ in }
    /// Pops until `depth` screens remain above the root.
    var pop: (_ depth: Int) -> Void = { _ in }
    var isShowing: (UUID) -> Bool = { _ in false }

    private func nextVersion() -> Int {
        version += 1
        return version
    }

    /// Stores the builder for values of `type`. Returns the version to report to the stack.
    func register<D>(_ type: D.Type, _ destination: @escaping (AnyHashable) -> AnyView) -> Int where D: Hashable {
        destinations[ObjectIdentifier(type)] = destination
        return nextVersion()
    }

    func destination(for value: AnyHashable) -> AnyView? {
        destinations[ObjectIdentifier(type(of: value.base))]?(value)
    }

    /// Stores the content of the screen `id`. Returns the version to report to the stack.
    func setView(_ view: AnyView, for id: UUID) -> Int {
        views[id] = view
        leaving.removeAll { $0 == id }
        return nextVersion()
    }

    func view(for id: UUID) -> AnyView? {
        views[id]
    }

    func onRemoval(of id: UUID, _ action: @escaping () -> Void) {
        removalActions[id] = action
    }

    /// Called by the stack when the screens `ids` have left it.
    func removed(_ ids: [UUID]) {
        for id in leaving {
            views[id] = nil
        }
        leaving = ids
        for id in ids {
            removalActions.removeValue(forKey: id)?()
        }
    }
}

private struct NavigatorKey: EnvironmentKey {
    static var defaultValue: Navigator? { nil }
}

private struct NavigationScreenIndexKey: EnvironmentKey {
    static var defaultValue: Int { 0 }
}

extension EnvironmentValues {
    var navigator: Navigator? {
        get { self[NavigatorKey.self] }
        set { self[NavigatorKey.self] = newValue }
    }

    /// The position in the stack of the screen a view is in; the root is 0.
    var navigationScreenIndex: Int {
        get { self[NavigationScreenIndexKey.self] }
        set { self[NavigationScreenIndexKey.self] = newValue }
    }
}

// MARK: - Preferences read by the stack

/// The newest version stored from each screen, by the screen's index.
struct NavigationRefreshKey: PreferenceKey {
    static var defaultValue: [Int: Int] { [:] }

    static func reduce(value: inout [Int: Int], nextValue: () -> [Int: Int]) {
        value.merge(nextValue()) { max($0, $1) }
    }
}

struct NavigationTitleKey: PreferenceKey {
    static var defaultValue: Text? { nil }

    static func reduce(value: inout Text?, nextValue: () -> Text?) {
        value = value ?? nextValue()
    }
}

struct NavigationTitleDisplayModeKey: PreferenceKey {
    static var defaultValue: NavigationBarItem.TitleDisplayMode? { nil }

    static func reduce(
        value: inout NavigationBarItem.TitleDisplayMode?,
        nextValue: () -> NavigationBarItem.TitleDisplayMode?
    ) {
        value = value ?? nextValue()
    }
}

struct NavigationBackButtonHiddenKey: PreferenceKey {
    static var defaultValue: Bool { false }

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Reports `version` as stored from the screen the content is in.
private struct NavigationRefreshModifier: ViewModifier {
    var version: Int?
    @Environment(\.navigationScreenIndex) private var screenIndex

    func body(content: Content) -> some View {
        content.transformPreference(NavigationRefreshKey.self) { versions in
            if let version {
                versions[screenIndex] = max(versions[screenIndex] ?? 0, version)
            }
        }
    }
}

// MARK: - Titles

/// A configuration for a navigation bar that represents a view at the top of a navigation stack.
public struct NavigationBarItem: Sendable {
    /// A style for displaying the title of a navigation bar.
    public enum TitleDisplayMode: Sendable {
        /// Inherit the display mode from the previous navigation item; large on the root.
        case automatic
        /// Display the title within the standard bounds of the navigation bar.
        case inline
        /// Display a large title within an expanded navigation bar.
        case large
    }
}

extension View {
    public func navigationTitle(_ title: Text) -> some View {
        preference(key: NavigationTitleKey.self, value: title)
    }

    public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View {
        navigationTitle(Text(titleKey))
    }

    @_disfavoredOverload
    public func navigationTitle<S>(_ title: S) -> some View where S: StringProtocol {
        navigationTitle(Text(title))
    }

    public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        preference(key: NavigationTitleDisplayModeKey.self, value: displayMode)
    }

    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        preference(key: NavigationBackButtonHiddenKey.self, value: hidesBackButton)
    }
}

// MARK: - Destinations

extension View {
    /// Associates a destination view with a presented data type for use within a navigation
    /// stack.
    public func navigationDestination<D, C>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View where D: Hashable, C: View {
        modifier(NavigationDestinationModifier(destination: destination))
    }

    /// Associates a destination view with a binding that can be used to push the view onto a
    /// navigation stack.
    public func navigationDestination<V>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: () -> V
    ) -> some View where V: View {
        modifier(NavigationFlagDestinationModifier(isPresented: isPresented, destination: destination()))
    }

    /// Associates a destination view with a bound value for use within a navigation stack.
    public func navigationDestination<D, C>(
        item: Binding<D?>,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View where D: Hashable, C: View {
        modifier(NavigationItemDestinationModifier(item: item, destination: destination))
    }
}

private struct NavigationDestinationModifier<D, C>: ViewModifier where D: Hashable, C: View {
    var destination: (D) -> C
    @Environment(\.navigator) private var navigator

    func body(content: Content) -> some View {
        let version = navigator?.register(D.self) { [destination] value in
            AnyView(destination(value.base as! D))
        }
        content.modifier(NavigationRefreshModifier(version: version))
    }
}

private struct NavigationFlagDestinationModifier<V>: ViewModifier where V: View {
    // A property, so that a change to the caller's state re-evaluates this modifier.
    @Binding var isPresented: Bool
    var destination: V

    func body(content: Content) -> some View {
        content.modifier(NavigationViewPresenter(
            view: isPresented ? AnyView(destination) : nil,
            dismiss: { isPresented = false }
        ))
    }
}

private struct NavigationItemDestinationModifier<D, C>: ViewModifier where D: Hashable, C: View {
    @Binding var item: D?
    var destination: (D) -> C

    func body(content: Content) -> some View {
        content.modifier(NavigationViewPresenter(
            view: item.map { AnyView(destination($0)) },
            dismiss: { item = nil }
        ))
    }
}

/// Keeps one screen in the stack for as long as `view` is not nil.
private struct NavigationViewPresenter: ViewModifier {
    var view: AnyView?
    /// Tells the caller that the screen left the stack some other way, such as the back button.
    var dismiss: () -> Void
    @Environment(\.navigator) private var navigator
    @State private var id = UUID()

    func body(content: Content) -> some View {
        let version = view.flatMap { navigator?.setView($0, for: id) }
        content
            .onChange(of: view != nil, initial: true) { _, isPresented in
                guard let navigator else { return }
                if isPresented {
                    navigator.onRemoval(of: id, dismiss)
                    if !navigator.isShowing(id) { navigator.pushView(id) }
                } else if navigator.isShowing(id) {
                    navigator.popView(id)
                }
            }
            .modifier(NavigationRefreshModifier(version: version))
    }
}

// MARK: - Dismiss

/// An action that dismisses a presentation: here, pops the screen it was read in.
public struct DismissAction {
    var action: () -> Void

    public func callAsFunction() {
        action()
    }
}

private struct DismissActionKey: EnvironmentKey {
    static var defaultValue: DismissAction { DismissAction(action: {}) }
}

extension EnvironmentValues {
    public internal(set) var dismiss: DismissAction {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }
}

// MARK: - NavigationLink

/// A view that controls a navigation presentation.
public struct NavigationLink<Label, Destination>: View where Label: View, Destination: View {
    fileprivate enum Target {
        case value(AnyHashable?)
        case view(AnyView)
    }

    private var label: Label
    private var target: Target
    @Environment(\.navigator) private var navigator
    /// Names the screen this link pushes when it carries its destination view.
    @State private var id = UUID()

    fileprivate init(label: Label, target: Target) {
        self.label = label
        self.target = target
    }

    public var body: some View {
        label
            .contentShape(Rectangle())
            .onTapGesture {
                guard let navigator else { return }
                switch target {
                case let .value(value):
                    if let value { navigator.push(value) }
                case let .view(view):
                    guard !navigator.isShowing(id) else { return }
                    _ = navigator.setView(view, for: id)
                    navigator.pushView(id)
                }
            }
            .modifier(NavigationRefreshModifier(version: shownViewVersion))
    }

    /// While this link's destination is on the stack, keeps it current.
    private var shownViewVersion: Int? {
        guard case let .view(view) = target, let navigator, navigator.isShowing(id) else { return nil }
        return navigator.setView(view, for: id)
    }
}

extension NavigationLink where Destination == Never {
    /// Creates a navigation link that presents the view corresponding to a value.
    public init<P>(value: P?, @ViewBuilder label: () -> Label) where P: Hashable {
        self.init(label: label(), target: .value(value.map { AnyHashable($0) }))
    }

    public init<P>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text, P: Hashable {
        self.init(label: Text(titleKey), target: .value(value.map { AnyHashable($0) }))
    }

    @_disfavoredOverload
    public init<S, P>(_ title: S, value: P?) where Label == Text, S: StringProtocol, P: Hashable {
        self.init(label: Text(title), target: .value(value.map { AnyHashable($0) }))
    }
}

extension NavigationLink {
    /// Creates a navigation link that presents the destination view.
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.init(label: label(), target: .view(AnyView(destination())))
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder destination: () -> Destination) where Label == Text {
        self.init(label: Text(titleKey), target: .view(AnyView(destination())))
    }

    @_disfavoredOverload
    public init<S>(_ title: S, @ViewBuilder destination: () -> Destination) where Label == Text, S: StringProtocol {
        self.init(label: Text(title), target: .view(AnyView(destination())))
    }
}
