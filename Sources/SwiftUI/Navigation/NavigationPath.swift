//
//  NavigationPath.swift
//  SwiftUI
//
//  Not implemented: `codable` and `CodableRepresentation`.

/// A type-erased list of data representing the content of a navigation stack.
public struct NavigationPath: Equatable {
    var elements: [AnyHashable]

    public init() {
        elements = []
    }

    public init<S>(_ elements: S) where S: Sequence, S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    public var count: Int { elements.count }

    public var isEmpty: Bool { elements.isEmpty }

    public mutating func append<V>(_ value: V) where V: Hashable {
        elements.append(AnyHashable(value))
    }

    public mutating func removeLast(_ k: Int = 1) {
        elements.removeLast(k)
    }
}
