//
//  NavigationStack.swift
//  SwiftUI
//
//  A navigation stack written against OpenSwiftUI's public API only. Apple's is backed by
//  UINavigationController; here the bars, the push and pop animation and the swipe back from
//  the leading edge are views, transitions and a gesture.
//
//  Every screen below the top one stays in the hierarchy, so its state survives.
//
//  Known differences from UIKit: a large title does not snap open or closed when a scroll ends
//  half way; the bars have no blur; a swipe back that starts over a scroll view also scrolls it.

import Foundation
public import OpenSwiftUI

// MARK: - Model

private enum NavigationEntry {
    /// Presented by `navigationDestination(for:)`; part of the path.
    case value(AnyHashable)
    /// Pushed with a view, whose content the navigator holds; not part of the path.
    case view(UUID)

    var value: AnyHashable? {
        if case let .value(value) = self { return value }
        return nil
    }

    var viewID: UUID? {
        if case let .view(id) = self { return id }
        return nil
    }
}

private struct NavigationScreenID: Hashable {
    enum Kind: Hashable {
        case root
        case value(AnyHashable)
        case view(UUID)
    }

    var kind: Kind
    /// How many screens of the same kind are under this one. A screen is not identified by
    /// its position, which changes when screens under it are popped.
    var occurrence: Int
}

private struct NavigationScreen: Identifiable {
    var id: NavigationScreenID
    /// Position in the stack; the root is 0.
    var index: Int
    var content: AnyView
}

/// What a screen's content has told the stack through preferences.
private struct NavigationScreenInfo {
    var title: Text?
    var displayMode: NavigationBarItem.TitleDisplayMode?
    var hidesBackButton = false
    var toolbar: [ToolbarEntry] = []
    /// A scroll view in the screen draws the large title, so that it scrolls with the content.
    var scrollShowsTitle = false
    /// That scroll view has moved the large title out of sight.
    var isTitleCollapsed = false
}

/// How to read and change a caller-owned path of type `Data`.
private struct PathAccess<Data> {
    var elements: (Data) -> [AnyHashable]
    var append: (inout Data, AnyHashable) -> Void
    var removeLast: (inout Data, Int) -> Void
}

private let navigationAnimation = Animation.spring(response: 0.4, dampingFraction: 1)
private let navigationBarHeight: CGFloat = 44
private let navigationBottomBarHeight: CGFloat = 49
/// How far, as a fraction of the width, a screen moves aside when another covers it.
private let coveredScreenShift: CGFloat = 0.3
/// A drag that starts this close to the leading edge can swipe the top screen away.
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
    /// The newest destination version stored from each screen; see NavigationSupport.swift.
    @State private var refresh: [Int: Int] = [:]
    @State private var info: [NavigationScreenID: NavigationScreenInfo] = [:]
    /// How far the top screen has been dragged toward the trailing edge by a swipe back.
    @State private var dragX: CGFloat = 0
    @State private var isSwipingBack = false
    @State private var width: CGFloat = 0
    /// The top of the area the screens are in, in global coordinates.
    @State private var contentTop: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0

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
        let large = largeTitleFlags(for: screens)
        let top = screens[screens.count - 1]
        let bottomItems = (info[top.id]?.toolbar ?? []).filter { $0.placement.slot == .bottom }
        VStack(spacing: 0) {
            bar(screens, isLarge: large[large.count - 1])
            ZStack(alignment: .leading) {
                ForEach(screens) { screen in
                    screenView(screen, topIndex: screens.count - 1, isLarge: large[screen.index])
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { contentTop = $0 }
            .clipped()
            .simultaneousGesture(
                backSwipe,
                including: screens.count > 1 && info[top.id]?.hidesBackButton != true ? .all : .subviews
            )
            if !bottomItems.isEmpty {
                bottomBar(bottomItems)
            }
        }
        .environment(\.navigator, navigator)
        .onPreferenceChange(NavigationRefreshKey.self) { refresh = $0 }
        .onChange(of: pathElements) { _, elements in
            if let elements { follow(elements) }
        }
        .onChange(of: screens.map(\.id)) { old, new in
            // A screen that just left is still on its way out and keeps what it reported.
            info = info.filter { new.contains($0.key) || old.contains($0.key) }
        }
    }

    // MARK: Screens

    private var screens: [NavigationScreen] {
        var screens = [NavigationScreen(id: .init(kind: .root, occurrence: 0), index: 0, content: AnyView(root))]
        var occurrences: [NavigationScreenID.Kind: Int] = [:]
        for (offset, entry) in stack.enumerated() {
            let index = offset + 1
            // Changes when a view in a screen below stores a destination again, which
            // re-evaluates this screen with it.
            let version = refresh.filter { $0.key < index }.values.max() ?? 0
            let kind: NavigationScreenID.Kind
            let content: AnyView
            switch entry {
            case let .value(value):
                kind = .value(value)
                content = AnyView(NavigationDestinationScreen(value: value, version: version))
            case let .view(id):
                kind = .view(id)
                content = AnyView(NavigationViewScreen(id: id, version: version))
            }
            let occurrence = occurrences[kind, default: 0]
            occurrences[kind] = occurrence + 1
            screens.append(NavigationScreen(
                id: .init(kind: kind, occurrence: occurrence),
                index: index,
                content: content
            ))
        }
        return screens
    }

    /// Whether each screen shows a large title. `automatic` takes after the screen below, and
    /// is large on the root; a screen without a title has no large title.
    private func largeTitleFlags(for screens: [NavigationScreen]) -> [Bool] {
        var isLargeMode = true
        return screens.map { screen in
            let info = info[screen.id]
            switch info?.displayMode ?? .automatic {
            case .automatic: break
            case .inline: isLargeMode = false
            case .large: isLargeMode = true
            }
            return isLargeMode && info?.title != nil
        }
    }

    private func screenView(_ screen: NavigationScreen, topIndex: Int, isLarge: Bool) -> some View {
        let id = screen.id
        let index = screen.index
        let isTop = index == topIndex
        let info = info[id]
        // 1 while fully covered, falling to 0 as a swipe back uncovers the screen under the top.
        let covered: CGFloat = isTop ? 0 : (index == topIndex - 1 && width > 0 ? 1 - dragX / width : 1)
        let largeTitle = isLarge ? info?.title : nil
        return screen.content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, largeTitle == nil ? 0 : navigationLargeTitleHeight)
            .overlay(
                info?.scrollShowsTitle == true ? nil : largeTitle.map { NavigationLargeTitleView(title: $0) },
                alignment: .top
            )
            .background(Color.white)
            .environment(\.navigationLargeTitle, largeTitle.map {
                NavigationLargeTitle(title: $0, height: navigationLargeTitleHeight, top: contentTop)
            })
            .environment(\.navigationScreenIndex, index)
            .transformEnvironment(\.dismiss) { dismiss in
                // The root keeps whatever presented the stack.
                if index > 0 {
                    dismiss = DismissAction { [navigator] in navigator.pop(index - 1) }
                }
            }
            .onPreferenceChange(NavigationTitleKey.self) { title in update(id) { $0.title = title } }
            .onPreferenceChange(NavigationTitleDisplayModeKey.self) { mode in update(id) { $0.displayMode = mode } }
            .onPreferenceChange(NavigationBackButtonHiddenKey.self) { hidden in update(id) { $0.hidesBackButton = hidden } }
            .onPreferenceChange(NavigationToolbarKey.self) { items in update(id) { $0.toolbar = items } }
            .onPreferenceChange(NavigationScrollShowsTitleKey.self) { shows in update(id) { $0.scrollShowsTitle = shows } }
            .onPreferenceChange(NavigationTitleCollapsedKey.self) { collapsed in
                withAnimation(.easeInOut(duration: 0.2)) {
                    update(id) { $0.isTitleCollapsed = collapsed }
                }
            }
            // The dimming is an opacity, not a colour of varying strength: a host that runs
            // animations by itself can be handed an opacity, and not a change of colour.
            .overlay(Color.black.opacity(0.1).opacity(Double(covered)).allowsHitTesting(false))
            // Whatever appears in the screen while it slides in, such as a title that is
            // reported a frame late, appears where the screen is and not where it is going.
            .geometryGroup()
            .offset(x: isTop ? dragX : -coveredScreenShift * width * covered)
            // A screen being removed must stay above the one it uncovers.
            .zIndex(Double(index))
            .transition(.move(edge: .trailing))
    }

    private func update(_ id: NavigationScreenID, _ change: (inout NavigationScreenInfo) -> Void) {
        change(&info[id, default: NavigationScreenInfo()])
    }

    // MARK: Bars

    private func bar(_ screens: [NavigationScreen], isLarge: Bool) -> some View {
        let top = screens[screens.count - 1]
        let info = info[top.id]
        let items = info?.toolbar ?? []
        let leading = items.filter { $0.placement.slot == .leading }
        let trailing = items.filter { $0.placement.slot == .trailing }
        let principal = items.first { $0.placement.slot == .principal }
        // A large title that is in sight replaces the one in the bar, and the bar blends
        // into the screen.
        let isExpanded = isLarge && info?.isTitleCollapsed != true
        let showsBack = screens.count > 1 && info?.hidesBackButton != true
        let previousTitle = screens.count > 1 ? self.info[screens[screens.count - 2].id]?.title : nil
        // A back button on its own gives way to the title; items keep the room they need.
        let leadingReserve = leading.isEmpty ? min(leadingWidth, 70) : leadingWidth
        let titleLimit = max(width - 2 * max(leadingReserve, trailingWidth) - 16, 0)
        return VStack(spacing: 0) {
            ZStack {
                Group {
                    if let principal {
                        principal.view
                    } else {
                        (info?.title ?? Text(""))
                            .font(.headline)
                            .lineLimit(1)
                            .opacity(isExpanded ? 0 : 1)
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { titleWidth = $0 }
                .frame(maxWidth: titleLimit)
                .id(top.id)
                .transition(.opacity)
                HStack(spacing: 0) {
                    HStack(spacing: toolbarItemSpacing) {
                        if showsBack {
                            backButton(
                                previousTitle: leading.isEmpty ? previousTitle : nil,
                                showsLabel: leading.isEmpty,
                                room: (width - (isExpanded ? 0 : titleWidth)) / 2 - 16
                            )
                        }
                        ForEach(Array(leading.enumerated()), id: \.offset) { $0.element.view }
                    }
                    .padding(.leading, showsBack ? 8 : 16)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { leadingWidth = $0 }
                    Spacer(minLength: 0)
                    HStack(spacing: toolbarItemSpacing) {
                        ForEach(Array(trailing.enumerated()), id: \.offset) { $0.element.view }
                    }
                    .padding(.trailing, 16)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { trailingWidth = $0 }
                }
                .id(top.id)
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: navigationBarHeight)
            .background(isExpanded ? Color.white : Color(white: 0.97))
            Rectangle()
                .fill(Color(white: 0.8))
                .frame(height: 0.5)
                .opacity(isExpanded ? 0 : 1)
        }
    }

    /// The chevron with the title of the screen it leads back to; with "Back" when that title
    /// does not fit in `room`, and alone when "Back" does not fit either.
    private func backButton(previousTitle: Text?, showsLabel: Bool, room: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            if let previousTitle {
                HStack(spacing: 5) {
                    NavigationBackChevron()
                    previousTitle.lineLimit(1)
                }
            }
            if showsLabel {
                HStack(spacing: 5) {
                    NavigationBackChevron()
                    Text("Back")
                }
            }
            NavigationBackChevron()
        }
        .foregroundStyle(Color.blue)
        .frame(maxWidth: max(room, 20), alignment: .leading)
        .frame(height: navigationBarHeight)
        .contentShape(Rectangle())
        .onTapGesture { pop(toDepth: stack.count - 1) }
    }

    private func bottomBar(_ items: [ToolbarEntry]) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(white: 0.8))
                .frame(height: 0.5)
            HStack(spacing: toolbarItemSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { $0.element.view }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: navigationBottomBarHeight)
            .background(Color(white: 0.97))
        }
    }

    // MARK: Swipe back

    /// Attached alongside the gestures of the screens, so a touch near the edge that never
    /// becomes a swipe still reaches what is under it.
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let startsAtEdge = value.startLocation.x <= backSwipeEdgeWidth
                let isHorizontal = value.translation.width > abs(value.translation.height)
                guard isSwipingBack || (startsAtEdge && isHorizontal) else { return }
                isSwipingBack = true
                dragX = max(value.translation.width, 0)
            }
            .onEnded { value in
                guard isSwipingBack else { return }
                isSwipingBack = false
                let far = value.translation.width > width * 0.35
                let fast = value.velocity.width > 300
                if value.translation.width > 0, far || fast {
                    pop(toDepth: stack.count - 1)
                } else {
                    withAnimation(navigationAnimation) { dragX = 0 }
                }
            }
    }

    // MARK: Changes

    private func bindNavigator() {
        navigator.push = { value in push(value) }
        navigator.pushView = { id in
            withAnimation(navigationAnimation) { stack.append(.view(id)) }
        }
        navigator.popView = { id in
            if let depth = stack.firstIndex(where: { $0.viewID == id }) {
                pop(toDepth: depth)
            }
        }
        navigator.pop = { depth in pop(toDepth: depth) }
        navigator.isShowing = { id in stack.contains { $0.viewID == id } }
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
        let popped = Array(stack[depth...])
        cut(to: depth)
        let poppedValues = popped.count { $0.value != nil }
        if poppedValues > 0, let access {
            access.removeLast(&path, poppedValues)
        }
        let poppedViews = popped.compactMap(\.viewID)
        if !poppedViews.isEmpty {
            navigator.removed(poppedViews)
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
        let removed = stack[kept.count...].compactMap(\.viewID)
        if matched == elements.count {
            cut(to: kept.count)
        } else {
            withAnimation(navigationAnimation) {
                stack = kept + elements[matched...].map { .value($0) }
                dragX = 0
            }
        }
        if !removed.isEmpty {
            navigator.removed(removed)
        }
    }

    /// Takes screens off the top until `depth` remain above the root.
    private func cut(to depth: Int) {
        guard depth < stack.count else { return }
        if stack.count - depth > 1 {
            // Only the top screen slides away. Those leaving from under it are hidden behind
            // it and go first, at once: sliding too, they would show beside it on the way.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                stack.removeSubrange(depth ..< stack.count - 1)
            }
        }
        withAnimation(navigationAnimation) {
            stack.removeLast()
            // The screen sliding away keeps the offset a swipe gave it; the next top starts at 0.
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

// MARK: - Screens above the root

private struct NavigationDestinationScreen: View {
    var value: AnyHashable
    var version: Int
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

private struct NavigationViewScreen: View {
    var id: UUID
    var version: Int
    @Environment(\.navigator) private var navigator

    var body: some View {
        navigator?.view(for: id)
    }
}

/// Drawn from two capsules: the renderer does not stroke paths.
private struct NavigationBackChevron: View {
    var body: some View {
        ZStack {
            Capsule()
                .frame(width: 12.5, height: 2.6)
                .rotationEffect(.degrees(-45))
                .offset(y: -4)
            Capsule()
                .frame(width: 12.5, height: 2.6)
                .rotationEffect(.degrees(45))
                .offset(y: 4)
        }
        .frame(width: 12, height: 22)
    }
}

// MARK: - Large titles

let navigationLargeTitleHeight: CGFloat = 52

/// What a screen with a large title tells a scroll view in it, which then takes over the
/// title so that it scrolls away with the content.
struct NavigationLargeTitle: Equatable {
    var title: Text
    /// The height the stack leaves free above the screen's content for the title.
    var height: CGFloat
    /// Where that space begins, in global coordinates.
    var top: CGFloat
}

private struct NavigationLargeTitleKey: EnvironmentKey {
    static var defaultValue: NavigationLargeTitle? { nil }
}

extension EnvironmentValues {
    var navigationLargeTitle: NavigationLargeTitle? {
        get { self[NavigationLargeTitleKey.self] }
        set { self[NavigationLargeTitleKey.self] = newValue }
    }
}

struct NavigationScrollShowsTitleKey: PreferenceKey {
    static var defaultValue: Bool { false }

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct NavigationTitleCollapsedKey: PreferenceKey {
    static var defaultValue: Bool { false }

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct NavigationLargeTitleView: View {
    var title: Text

    var body: some View {
        title
            .font(.largeTitle.bold())
            .lineLimit(1)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .frame(height: navigationLargeTitleHeight, alignment: .bottom)
            .allowsHitTesting(false)
    }
}
