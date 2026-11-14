//
//  PangoTextLayout.swift
//  OpenSwiftUI
//
//  Measures and draws Text with Pango. OpenSwiftUICore does not resolve fonts off Darwin
//  (they are CTFont-backed), so every run uses one fixed face and size; only the string,
//  wrapping, line limit, alignment and an explicit resolved color are honoured.

#if OPENSWIFTUI_GTK
import CGtk
import Foundation
import OpenCoreGraphicsShims
@_spi(ForOpenSwiftUIOnly) @_spi(Private) import OpenSwiftUICore

enum PangoTextLayout {
    /// SwiftUI's `.body` size on iOS at the default Dynamic Type size.
    private static let fontSize = 17.0
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

    private static func configure(
        _ layout: OpaquePointer,
        string: NSAttributedString,
        width: CGFloat,
        lineLimit: Int?
    ) {
        let description = pango_font_description_new()
        pango_font_description_set_family(description, "system-ui")
        pango_font_description_set_absolute_size(description, fontSize * scale)
        pango_layout_set_font_description(layout, description)
        pango_font_description_free(description)
        pango_layout_set_text(layout, string.string, -1)
        pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
        pango_layout_set_width(layout, width.isFinite ? Int32((width * scale).rounded(.down)) : -1)
        if let lineLimit {
            pango_layout_set_height(layout, -Int32(max(lineLimit, 1)))
            pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END)
        }
    }

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
        let color = storage.attribute(NSAttributedString.Key("NSColor"), at: 0, effectiveRange: nil) as? Color.Resolved
        cairo_set_source_rgba(
            cr,
            Double(color?.red ?? 0), Double(color?.green ?? 0), Double(color?.blue ?? 0), Double(color?.opacity ?? 1)
        )
        cairo_move_to(cr, origin.x, origin.y)
        pango_cairo_show_layout(cr, layout)
    }
}
#endif
