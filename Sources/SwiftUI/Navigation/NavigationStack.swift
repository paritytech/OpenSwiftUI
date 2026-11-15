//
//  NavigationStack.swift
//  SwiftUI
//
//  A navigation stack written against OpenSwiftUI's public API only. Apple's is backed by
//  UINavigationController; here the bar, the push and pop animation and the swipe back from
//  the leading edge are views, transitions and a gesture.
//
//  Every screen below the top one stays in the hierarchy, so its state survives.
//
//  Known differences from UIKit: the bar always shows an inline title; the back button always
//  reads "Back"; a 20-point strip at the leading edge of a pushed screen takes touches for the
//  swipe back, so content under it cannot be tapped; a destination that captured state from
//  the view that declared it is not rebuilt when that state changes.

import Foundation
public import OpenSwiftUI

// MARK: - Model

private enum NavigationEntry {
    /// Presented by `navigationDestination(for:)`; part of the path.
    case value(AnyHashable)
    /// Pushed by a link that carries its destination view; not part of the path.
    case view(UUID, AnyView)

    var value: AnyHashable? {
        if case let .value(value) = self { return value }
        return nil
    }
}

private struct NavigationScreenID: Hashable {
    enum Kind: Hashable {
        case root
        case value(AnyHashable)
        case view(UUID)
    }

    /// Position in the stack; the root is 0.
    var index: Int
    var kind: Kind
}

private struct NavigationScreen: Identifiable {
    var id: NavigationScreenID
    var content: AnyView
}

/// How to read and change a caller-owned path of type `Data`.
private struct PathAccess<Data> {
    var elements: (Data) -> [AnyHashable]
    var append: (inout Data, AnyHashable) -> Void
    var removeLast: (inout Data, Int) -> Void
}

private let navigationAnimation = Animation.spring(response: 0.4, dampingFraction: 1)
private let navigationBarHeight: CGFloat = 44
/// How far, as a fraction of the width, a screen moves aside when another covers it.
private let coveredScreenShift: CGFloat = 0.3
private let backSwipeEdgeWidth: CGFloat = 20

// MARK: - NavigationStack

/// A view that displays a root view and enables you to present additional views over it.
public struct NavigationStack<Data, Root>: View where Root: View {
    private var root: Root
    /// The caller's path, or a constant when the stack owns its state (`access` is nil then).
    /// It has to be a `Binding` property of the view: only then does a change to the path
    /// re-evaluate this view. A binding inside an Optional or a closure is not tracked.
    @Binding private var path: Data
    private var access: PathAccess<Data>?

    /// What is shown above the root. With a caller-owned path this follows the path.
    @State private var stack: [NavigationEntry]
    @State private var navigator = Navigator()
    @State private var destinationTypes: Set<ObjectIdentifier> = []
    @State private var titles: [NavigationScreenID: Text] = [:]
    @State private var backButtonHidden: Set<NavigationScreenID> = []
    /// How far the top screen has been dragged toward the trailing edge by a swipe back.
    @State private var dragX: CGFloat = 0
    @State private var width: CGFloat = 0

    private init(root: Root, path: Binding<Data>, access: PathAccess<Data>?) {
        self.root = root
        _path = path
        self.access = access
        let initial = access?.elements(path.wrappedValue) ?? []
        _stack = State(initialValue: initial.map { .value($0) })
    }

    /// The caller's path as type-erased values, or nil when the stack owns its state.
    private var pathElements: [AnyHashable]? {
        access?.elements(path)
    }

    public var body: some View {
        let _ = bindNavigator()
        let screens = self.screens
        VStack(spacing: 0) {
            bar(screens)
            ZStack(alignment: .leading) {
                ForEach(screens) { screen in
                    screenView(screen, topIndex: screens.count - 1)
                }
                if screens.count > 1 {
                    backSwipeEdge.zIndex(Double(screens.count))
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .clipped()
        }
        .environment(\.navigator, navigator)
        .onPreferenceChange(NavigationDestinationTypesKey.self) { destinationTypes = $0 }
        .onChange(of: pathElements) { _, elements in
            if let elements { follow(elements) }
        }
    }

    // MARK: Screens

    private var screens: [NavigationScreen] {
        var screens = [NavigationScreen(id: .init(index: 0, kind: .root), content: AnyView(root))]
        for (offset, entry) in stack.enumerated() {
            switch entry {
            case let .value(value):
                let type = ObjectIdentifier(type(of: value.base))
                screens.append(NavigationScreen(
                    id: .init(index: offset + 1, kind: .value(value)),
                    // `hasDestination` makes the screen re-evaluate once a destination for
                    // its type is registered.
                    content: AnyView(NavigationDestinationScreen(
                        value: value,
                        hasDestination: destinationTypes.contains(type)
                    ))
                ))
            case let .view(id, view):
                screens.append(NavigationScreen(id: .init(index: offset + 1, kind: .view(id)), content: view))
            }
        }
        return screens
    }

    private func screenView(_ screen: NavigationScreen, topIndex: Int) -> some View {
        let index = screen.id.index
        let isTop = index == topIndex
        // 1 while fully covered, falling to 0 as a swipe back uncovers the screen under the top.
        let covered: CGFloat = isTop ? 0 : (index == topIndex - 1 && width > 0 ? 1 - dragX / width : 1)
        return screen.content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .transformEnvironment(\.dismiss) { dismiss in
                // The root keeps whatever presented the stack.
                if index > 0 {
                    dismiss = DismissAction { [navigator] in navigator.pop(index - 1) }
                }
            }
            .onPreferenceChange(NavigationTitleKey.self) { titles[screen.id] = $0 }
            .onPreferenceChange(NavigationBackButtonHiddenKey.self) { hidden in
                if hidden { backButtonHidden.insert(screen.id) } else { backButtonHidden.remove(screen.id) }
            }
            .overlay(Color.black.opacity(0.1 * covered).allowsHitTesting(false))
            .offset(x: isTop ? dragX : -coveredScreenShift * width * covered)
            // A screen being removed must stay above the one it uncovers.
            .zIndex(Double(index))
            .transition(.move(edge: .trailing))
    }

    // MARK: Bar

    private func bar(_ screens: [NavigationScreen]) -> some View {
        let top = screens[screens.count - 1]
        return VStack(spacing: 0) {
            ZStack {
                (titles[top.id] ?? Text(""))
                    .lineLimit(1)
                    .id(top.id)
                    .transition(.opacity)
                HStack(spacing: 0) {
                    if screens.count > 1, !backButtonHidden.contains(top.id) {
                        HStack(spacing: 6) {
                            Text("‹")
                            Text("Back")
                        }
                        .padding(.horizontal, 14)
                        .frame(height: navigationBarHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { pop(toDepth: stack.count - 1) }
                        .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: navigationBarHeight)
            .background(Color(white: 0.97))
            Rectangle()
                .fill(Color(white: 0.8))
                .frame(height: 0.5)
        }
    }

    // MARK: Swipe back

    private var backSwipeEdge: some View {
        Color.clear
            .frame(width: backSwipeEdgeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        dragX = max(value.translation.width, 0)
                    }
                    .onEnded { value in
                        let far = value.translation.width > width * 0.35
                        let fast = value.velocity.width > 300
                        if value.translation.width > 0, far || fast {
                            pop(toDepth: stack.count - 1)
                        } else {
                            withAnimation(navigationAnimation) { dragX = 0 }
                        }
                    }
            )
    }

    // MARK: Changes

    private func bindNavigator() {
        navigator.push = { value in push(value) }
        navigator.pushView = { view in
            withAnimation(navigationAnimation) { stack.append(.view(UUID(), view)) }
        }
        navigator.pop = { depth in pop(toDepth: depth) }
        navigator.depth = { stack.count }
    }

    private func push(_ value: AnyHashable) {
        if let access {
            // The stack follows the path when the change comes back through `onChange`.
            access.append(&path, value)
        } else {
            withAnimation(navigationAnimation) { stack.append(.value(value)) }
        }
    }

    /// Pops until `depth` screens remain above the root.
    private func pop(toDepth depth: Int) {
        let depth = max(depth, 0)
        guard depth < stack.count else { return }
        let poppedValues = stack[depth...].reduce(0) { $0 + ($1.value == nil ? 0 : 1) }
        withAnimation(navigationAnimation) {
            stack.removeLast(stack.count - depth)
            // The screen sliding away keeps the offset a swipe gave it; the next top starts at 0.
            dragX = 0
        }
        if poppedValues > 0, let access {
            access.removeLast(&path, poppedValues)
        }
    }

    /// Makes the stack show a caller-owned path that changed.
    private func follow(_ elements: [AnyHashable]) {
        guard stack.compactMap(\.value) != elements else { return }
        // Keep the screens whose values still lead the path, with the view screens pushed
        // from them; everything from the first value that no longer matches goes.
        var kept: [NavigationEntry] = []
        var matched = 0
        for entry in stack {
            if let value = entry.value {
                guard matched < elements.count, elements[matched] == value else { break }
                matched += 1
            }
            kept.append(entry)
        }
        withAnimation(navigationAnimation) {
            stack = kept + elements[matched...].map { .value($0) }
            dragX = 0
        }
    }
}

extension NavigationStack where Data == NavigationPath {
    /// Creates a navigation stack that manages its own navigation state.
    public init(@ViewBuilder root: () -> Root) {
        self.init(root: root(), path: .constant(NavigationPath()), access: nil)
    }

    /// Creates a navigation stack with heterogeneous navigation state that you control.
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) {
        self.init(
            root: root(),
            path: path,
            access: PathAccess(
                elements: { $0.elements },
                append: { path, value in path.elements.append(value) },
                removeLast: { path, count in path.removeLast(count) }
            )
        )
    }
}

extension NavigationStack {
    /// Creates a navigation stack with homogeneous navigation state that you control.
    public init(path: Binding<Data>, @ViewBuilder root: () -> Root)
    where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection, Data.Element: Hashable {
        self.init(
            root: root(),
            path: path,
            access: PathAccess(
                elements: { $0.map { AnyHashable($0) } },
                append: { path, value in
                    // A link whose value is of another type has nowhere to go in this path.
                    if let element = value.base as? Data.Element {
                        path.append(element)
                    }
                },
                removeLast: { path, count in path.removeLast(count) }
            )
        )
    }
}

// MARK: - Destination screen

private struct NavigationDestinationScreen: View {
    var value: AnyHashable
    var hasDestination: Bool
    @Environment(\.navigator) private var navigator

    var body: some View {
        if let destination = navigator?.destination(for: value) {
            destination
        } else {
            Text("No navigationDestination(for: \(String(describing: type(of: value.base))).self) is declared in this stack.")
                .padding(24)
        }
    }
}
