//
//  FontNonDarwinShims.swift
//  OpenSwiftUICore
//
//  CoreText is not available off Darwin. These stand in for its font types and carry what a
//  `Font` resolves to, so that a host can pick a face with its own text system.

#if !canImport(CoreText)
public import Foundation

public final class CTFontDescriptor: CFCompatObject {
    /// A family asked for by name. Nil is the system interface font in `design`.
    package var family: String?
    package var design: Font.Design
    package var size: CGFloat
    /// On the scale of `Font.Weight`: 0 is regular, 0.4 is bold.
    package var weight: CGFloat
    /// On the scale of `Font.Width`: 0 is standard, negative is narrower.
    package var width: CGFloat = 0
    package var isItalic = false
    package var hasMonospacedDigits = false
    package var leading: Font.Leading = .standard

    package init(family: String? = nil, design: Font.Design = .default, size: CGFloat, weight: CGFloat = 0) {
        self.family = family
        self.design = design
        self.size = size
        self.weight = weight
        super.init()
    }

    package func copy() -> CTFontDescriptor {
        let copy = CTFontDescriptor(family: family, design: design, size: size, weight: weight)
        copy.width = width
        copy.isItalic = isItalic
        copy.hasMonospacedDigits = hasMonospacedDigits
        copy.leading = leading
        return copy
    }
}

public final class CTFont: CFCompatObject {
    package let descriptor: CTFontDescriptor

    package init(descriptor: CTFontDescriptor) {
        self.descriptor = descriptor
        super.init()
    }
}

extension Font.TextStyle {
    /// The point size and weight of the style on iOS at the default Dynamic Type size.
    package var defaultMetrics: (size: CGFloat, weight: Font.Weight) {
        switch self {
        case .largeTitle: (34, .regular)
        case .title: (28, .regular)
        case .title2: (22, .regular)
        case .title3: (20, .regular)
        case .headline: (17, .semibold)
        case .subheadline: (15, .regular)
        case .body: (17, .regular)
        case .callout: (16, .regular)
        case .footnote: (13, .regular)
        case .caption: (12, .regular)
        case .caption2: (11, .regular)
        case .extraLargeTitle: (36, .bold)
        case .extraLargeTitle2: (28, .bold)
        case .caption3: (10, .regular)
        }
    }
}

extension DynamicTypeSize {
    /// The body size on iOS at this Dynamic Type size, relative to the default size. Every
    /// text style is scaled by it; CoreText has a table for each style instead.
    package var bodySizeRatio: CGFloat {
        let bodySize: CGFloat = switch self {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        }
        return bodySize / 17
    }
}

#endif
