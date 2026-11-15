//
//  BorderlessFallbackButtonStyle.swift
//  OpenSwiftUI
//
//  The look of a button where there is no platform button to follow: the label in the tint
//  colour, dimmed while pressed, as a borderless button on iOS. Off Darwin the default and
//  the borderless style both resolve to it.

#if !canImport(Darwin)
import OpenSwiftUICore

struct BorderlessFallbackButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .modifier(OpacityButtonHighlightModifier(highlighted: configuration.isPressed))
        }
        .contentShape(Rectangle())
        .defaultForegroundStyle(foregroundStyle(role: configuration.role))
    }

    private func foregroundStyle(role: ButtonRole?) -> AnyShapeStyle {
        if !isEnabled {
            AnyShapeStyle(HierarchicalShapeStyle.tertiary)
        } else if role == .destructive {
            AnyShapeStyle(Color.red)
        } else {
            AnyShapeStyle(TintShapeStyle())
        }
    }
}
#endif
