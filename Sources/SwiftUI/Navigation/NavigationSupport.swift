//
//  NavigationSupport.swift
//  SwiftUI
//
//  What views inside a NavigationStack use to talk to it: links, destinations, titles, dismiss.
//
//  Not implemented: large titles and `navigationBarTitleDisplayMode`, `toolbar` items in the
//  bar, `navigationDestination(isPresented:)` and `navigationDestination(item:)`.

import Foundation
public import OpenSwiftUI

// MARK: - Navigator

/// The stack's side of the conversation, shared through the environment. A reference, so that
/// registering a destination while a view's body runs does not itself change any view state.
final class Navigator {
    /// Destination builders by the type of value they present.
    private(set) var destinations: [ObjectIdentifier: (AnyHashable) -> AnyView] = [:]

    var push: (AnyHashable) -> Void = { _ in }
    var pushView: (AnyView) -> Void = { _ in }
    /// Pops until `depth` screens remain above the root.
    var pop: (_ depth: Int) -> Void = { _ in }
    var depth: () -> Int = { 0 }

    func register<D>(_ type: D.Type, _ destination: @escaping (AnyHashable) -> AnyView) where D: Hashable {
        destinations[ObjectIdentifier(type)] = destination
    }

    func destination(for value: AnyHashable) -> AnyView? {
        destinations[ObjectIdentifier(type(of: value.base))]?(value)
    }
}

private struct NavigatorKey: EnvironmentKey {
    static var defaultValue: Navigator? { nil }
}

extension EnvironmentValues {
    var navigator: Navigator? {
        get { self[NavigatorKey.self] }
        set { self[NavigatorKey.self] = newValue }
    }
}

// MARK: - Preferences read by the stack

/// The value types that have a destination, so the stack re-evaluates its screens when one is
/// registered after a value of that type was pushed.
struct NavigationDestinationTypesKey: PreferenceKey {
    static var defaultValue: Set<ObjectIdentifier> { [] }

    static func reduce(value: inout Set<ObjectIdentifier>, nextValue: () -> Set<ObjectIdentifier>) {
        value.formUnion(nextValue())
    }
}

struct NavigationTitleKey: PreferenceKey {
    static var defaultValue: Text? { nil }

    static func reduce(value: inout Text?, nextValue: () -> Text?) {
        value = value ?? nextValue()
    }
}

struct NavigationBackButtonHiddenKey: PreferenceKey {
    static var defaultValue: Bool { false }

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - View modifiers

extension View {
    /// Associates a destination view with a presented data type for use within a navigation
    /// stack.
    public func navigationDestination<D, C>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View where D: Hashable, C: View {
        modifier(NavigationDestinationModifier(destination: destination))
    }

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

    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        preference(key: NavigationBackButtonHiddenKey.self, value: hidesBackButton)
    }
}

private struct NavigationDestinationModifier<D, C>: ViewModifier where D: Hashable, C: View {
    var destination: (D) -> C
    @Environment(\.navigator) private var navigator

    func body(content: Content) -> some View {
        // Registered on every evaluation, so the builder always captures current state.
        let _ = navigator?.register(D.self) { [destination] value in
            AnyView(destination(value.base as! D))
        }
        content.transformPreference(NavigationDestinationTypesKey.self) { types in
            types.insert(ObjectIdentifier(D.self))
        }
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

    fileprivate init(label: Label, target: Target) {
        self.label = label
        self.target = target
    }

    public var body: some View {
        label
            .contentShape(Rectangle())
            .onTapGesture {
                switch target {
                case let .value(value):
                    if let value { navigator?.push(value) }
                case let .view(view):
                    navigator?.pushView(view)
                }
            }
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
