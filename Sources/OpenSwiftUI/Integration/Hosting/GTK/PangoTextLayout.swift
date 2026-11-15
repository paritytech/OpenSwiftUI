//
//  PangoTextLayout.swift
//  OpenSwiftUI
//
//  Measures and draws Text with Pango. OpenSwiftUICore resolves each run of a Text to an
//  attributed string; the font of a run is a `CTFont` stand-in that says which face is
//  wanted (FontNonDarwinShims.swift), and this file maps it to a Pango font description.
//
//  Honoured: font (size, weight, italic, design, width, named family, monospaced digits),
//  foreground and background colour, underline, strikethrough, kerning, tracking, baseline
//  offset, wrapping, line limit and alignment. Not honoured: font leading, line spacing,
//  truncation mode, shadows and attachments.

#if OPENSWIFTUI_GTK
import CGtk
import Foundation
import OpenCoreGraphicsShims
@_spi(ForOpenSwiftUIOnly) @_spi(Private) import OpenSwiftUICore

enum PangoTextLayout {
    /// SwiftUI's `.body` size on iOS at the default Dynamic Type size, for a run without a font.
    private static let defaultFontSize = 17.0
    private static let scale = Double(PANGO_SCALE)

    static func install() {
        PlatformTextMeasurer.measure = { string, requestedSize, lineLimit in
            measure(string, requestedSize: requestedSize, lineLimit: lineLimit)
        }
    }

    private static let measuringContext: OpaquePointer = {
        let context: OpaquePointer = pango_font_map_create_context(pango_cairo_font_map_get_default())
        pango_cairo_context_set_font_options(context, fontOptions)
        return context
    }()

    /// Unhinted metrics, so a layout measures the same at every display scale and the
    /// drawn text wraps exactly where the measured text did.
    private static let fontOptions: OpaquePointer = {
        let options: OpaquePointer = cairo_font_options_create()
        cairo_font_options_set_hint_metrics(options, CAIRO_HINT_METRICS_OFF)
        cairo_font_options_set_hint_style(options, CAIRO_HINT_STYLE_NONE)
        return options
    }()

    // MARK: Fonts

    /// The caller frees the description.
    private static func fontDescription(_ descriptor: CTFontDescriptor?) -> OpaquePointer {
        let description: OpaquePointer = pango_font_description_new()
        let family = descriptor?.family ?? {
            switch descriptor?.design ?? .default {
            case .default: "system-ui"
            case .serif: "serif"
            case .rounded: "ui-rounded,system-ui"
            case .monospaced: "monospace"
            }
        }()
        pango_font_description_set_family(description, family)
        let size = descriptor.map { Double($0.size) } ?? defaultFontSize
        pango_font_description_set_absolute_size(description, size * scale)
        guard let descriptor else { return description }
        pango_font_description_set_weight(description, PangoWeight(rawValue: pangoWeight(descriptor.weight)))
        if descriptor.isItalic {
            pango_font_description_set_style(description, PANGO_STYLE_ITALIC)
        }
        if descriptor.width <= -0.3 {
            pango_font_description_set_stretch(description, PANGO_STRETCH_EXTRA_CONDENSED)
        } else if descriptor.width <= -0.1 {
            pango_font_description_set_stretch(description, PANGO_STRETCH_CONDENSED)
        } else if descriptor.width >= 0.1 {
            pango_font_description_set_stretch(description, PANGO_STRETCH_EXPANDED)
        }
        return description
    }

    /// `Font.Weight` values and the CSS weights they name.
    private static let weights: [(value: Double, css: Double)] = [
        (-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900),
    ]

    private static func pangoWeight(_ weight: CGFloat) -> UInt32 {
        let weight = Double(weight)
        guard weight > weights[0].value else { return UInt32(weights[0].css) }
        for (lower, upper) in zip(weights, weights.dropFirst()) where weight <= upper.value {
            let fraction = (weight - lower.value) / (upper.value - lower.value)
            return UInt32((lower.css + fraction * (upper.css - lower.css)).rounded())
        }
        return UInt32(weights[weights.count - 1].css)
    }

    // MARK: Attributes

    private static func attributes(of string: NSAttributedString) -> OpaquePointer {
        let list: OpaquePointer = pango_attr_list_new()
        let text = string.string
        let utf16 = text.utf16
        // Pango indexes by UTF-8 byte, NSAttributedString by UTF-16 unit.
        func byteOffset(_ utf16Offset: Int) -> UInt32 {
            let index = utf16.index(utf16.startIndex, offsetBy: utf16Offset)
            return UInt32(text.utf8.distance(from: text.utf8.startIndex, to: index))
        }
        func component(_ value: CGFloat) -> UInt16 {
            UInt16((min(max(Double(value), 0), 1) * 65535).rounded())
        }
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attributes, range, _ in
            let start = byteOffset(range.location)
            let end = byteOffset(range.location + range.length)
            func add(_ attribute: UnsafeMutablePointer<PangoAttribute>?) {
                guard let attribute else { return }
                attribute.pointee.start_index = start
                attribute.pointee.end_index = end
                pango_attr_list_insert(list, attribute)
            }
            if let font = attributes[.kitFont] as? CTFont {
                let description = fontDescription(font.descriptor)
                add(pango_attr_font_desc_new(description))
                pango_font_description_free(description)
                if font.descriptor.hasMonospacedDigits {
                    add(pango_attr_font_features_new("tnum=1"))
                }
            }
            if let color = attributes[.kitForegroundColor] as? NDColor {
                add(pango_attr_foreground_new(component(color.red), component(color.green), component(color.blue)))
                add(pango_attr_foreground_alpha_new(component(color.alpha)))
            }
            if let color = attributes[.kitBackgroundColor] as? NDColor {
                add(pango_attr_background_new(component(color.red), component(color.green), component(color.blue)))
                add(pango_attr_background_alpha_new(component(color.alpha)))
            }
            if let style = attributes[.kitUnderlineStyle] as? NSNumber, style.intValue != 0 {
                add(pango_attr_underline_new(PANGO_UNDERLINE_SINGLE))
                if let color = attributes[.kitUnderlineColor] as? NDColor {
                    add(pango_attr_underline_color_new(component(color.red), component(color.green), component(color.blue)))
                }
            }
            if let style = attributes[.kitStrikethroughStyle] as? NSNumber, style.intValue != 0 {
                add(pango_attr_strikethrough_new(1))
                if let color = attributes[.kitStrikethroughColor] as? NDColor {
                    add(pango_attr_strikethrough_color_new(component(color.red), component(color.green), component(color.blue)))
                }
            }
            let spacing = (attributes[.kitKern] as? CGFloat ?? 0) + (attributes[.kitTracking] as? CGFloat ?? 0)
            if spacing != 0 {
                add(pango_attr_letter_spacing_new(Int32((Double(spacing) * scale).rounded())))
            }
            if let offset = attributes[.kitBaselineOffset] as? CGFloat, offset != 0 {
                add(pango_attr_rise_new(Int32((Double(offset) * scale).rounded())))
            }
        }
        return list
    }

    private static func configure(
        _ layout: OpaquePointer,
        string: NSAttributedString,
        width: CGFloat,
        lineLimit: Int?
    ) {
        let description = fontDescription(nil)
        pango_layout_set_font_description(layout, description)
        pango_font_description_free(description)
        pango_layout_set_text(layout, string.string, -1)
        let attributes = attributes(of: string)
        pango_layout_set_attributes(layout, attributes)
        pango_attr_list_unref(attributes)
        pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
        pango_layout_set_width(layout, width.isFinite ? Int32((width * scale).rounded(.down)) : -1)
        if let lineLimit {
            pango_layout_set_height(layout, -Int32(max(lineLimit, 1)))
            pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END)
        }
    }

    // MARK: Measuring and drawing

    private static func measure(
        _ string: NSAttributedString,
        requestedSize: CGSize,
        lineLimit: Int?
    ) -> PlatformTextMetrics {
        guard string.length > 0, let layout = pango_layout_new(measuringContext) else {
            return PlatformTextMetrics(size: .zero, firstBaseline: 0, lastBaseline: 0, numberOfLines: 0)
        }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        configure(layout, string: string, width: requestedSize.width, lineLimit: lineLimit)
        var logical = PangoRectangle()
        pango_layout_get_extents(layout, nil, &logical)
        let firstBaseline = Double(pango_layout_get_baseline(layout)) / scale
        var lastBaseline = firstBaseline
        if let iterator = pango_layout_get_iter(layout) {
            repeat {
                lastBaseline = Double(pango_layout_iter_get_baseline(iterator)) / scale
            } while pango_layout_iter_next_line(iterator) != 0
            pango_layout_iter_free(iterator)
        }
        return PlatformTextMetrics(
            size: CGSize(
                width: (Double(logical.width) / scale).rounded(.up),
                height: (Double(logical.height) / scale).rounded(.up)
            ),
            firstBaseline: firstBaseline,
            lastBaseline: lastBaseline,
            numberOfLines: Int(pango_layout_get_line_count(layout))
        )
    }

    static func draw(_ view: StyledTextContentView, size: CGSize, origin: CGPoint, in cr: OpaquePointer) {
        guard let storage = view.text.storage, storage.length > 0,
              let layout = pango_cairo_create_layout(cr) else {
            return
        }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        pango_cairo_context_set_font_options(pango_layout_get_context(layout), fontOptions)
        pango_layout_context_changed(layout)
        let properties = view.text.layoutProperties
        configure(layout, string: storage, width: size.width, lineLimit: properties.lineLimit)
        switch properties.multilineTextAlignment {
        case .leading: pango_layout_set_alignment(layout, PANGO_ALIGN_LEFT)
        case .center: pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER)
        case .trailing: pango_layout_set_alignment(layout, PANGO_ALIGN_RIGHT)
        }
        // A run without a colour of its own is drawn in the label colour.
        cairo_set_source_rgba(cr, 0, 0, 0, 1)
        cairo_move_to(cr, origin.x, origin.y)
        pango_cairo_show_layout(cr, layout)
    }
}
#endif
