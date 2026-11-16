//
//  CairoDisplayListRenderer.swift
//  OpenSwiftUI
//
//  Paints an OpenSwiftUI display list with Cairo. Child lists of an effect item are in the
//  item's coordinate space (origin at `item.position`), as in upstream's SDLViewUpdater.

#if OPENSWIFTUI_GTK
import CGtk
import Foundation
import OpenCoreGraphicsShims
@_spi(ForOpenSwiftUIOnly) import OpenSwiftUICore

struct CairoDisplayListRenderer {
    let cr: OpaquePointer

    func clear(size: CGSize) {
        cairo_set_source_rgb(cr, 1, 1, 1)
        cairo_paint(cr)
    }

    func draw(_ list: DisplayList) {
        for item in list.items {
            draw(item)
        }
    }

    private func draw(_ item: DisplayList.Item) {
        switch item.value {
        case .empty:
            break
        case let .content(content):
            draw(content, frame: item.frame)
        case let .effect(effect, list):
            cairo_save(cr)
            cairo_translate(cr, item.position.x, item.position.y)
            draw(effect, list)
            cairo_restore(cr)
        case let .states(states):
            for (_, list) in states {
                draw(list)
            }
        }
    }

    // MARK: Content

    private func draw(_ content: DisplayList.Content, frame: CGRect) {
        switch content.value {
        case let .color(color):
            setSource(color)
            cairo_rectangle(cr, frame.minX, frame.minY, frame.width, frame.height)
            cairo_fill(cr)
        case let .shape(path, paint, fillStyle):
            cairo_save(cr)
            cairo_translate(cr, frame.minX, frame.minY)
            if addPath(path), setSource(paint, bounds: CGRect(origin: .zero, size: frame.size)) {
                cairo_set_fill_rule(cr, fillStyle.isEOFilled ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
                cairo_set_antialias(cr, fillStyle.isAntialiased ? CAIRO_ANTIALIAS_DEFAULT : CAIRO_ANTIALIAS_NONE)
                cairo_fill(cr)
            }
            cairo_new_path(cr)
            cairo_restore(cr)
        case let .text(view, size):
            PangoTextLayout.draw(view, size: size, origin: frame.origin, in: cr)
        case let .flattened(list, offset, _):
            cairo_save(cr)
            cairo_translate(cr, frame.minX + offset.x, frame.minY + offset.y)
            draw(list)
            cairo_restore(cr)
        case .shadow:
            Self.unsupported("shadow content")
        case .image:
            Self.unsupported("image content")
        default:
            Self.unsupported("content \(content.value)")
        }
    }

    // MARK: Effects

    private func draw(_ effect: DisplayList.Effect, _ list: DisplayList) {
        switch effect {
        case let .opacity(alpha):
            cairo_push_group(cr)
            draw(list)
            cairo_pop_group_to_source(cr)
            cairo_paint_with_alpha(cr, Double(alpha))
        case let .clip(path, fillStyle, _):
            if addPath(path) {
                cairo_set_fill_rule(cr, fillStyle.isEOFilled ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
                cairo_clip(cr)
            }
            draw(list)
        case let .mask(mask, _):
            cairo_push_group(cr)
            draw(list)
            let content = cairo_pop_group(cr)
            cairo_push_group(cr)
            draw(mask)
            let maskPattern = cairo_pop_group(cr)
            cairo_set_source(cr, content)
            cairo_mask(cr, maskPattern)
            cairo_pattern_destroy(maskPattern)
            cairo_pattern_destroy(content)
        case let .transform(transform):
            switch transform {
            case let .affine(affine):
                var matrix = cairo_matrix_t(
                    xx: affine.a, yx: affine.b,
                    xy: affine.c, yy: affine.d,
                    x0: affine.tx, y0: affine.ty
                )
                cairo_transform(cr, &matrix)
            case let .rotation(data):
                cairo_translate(cr, data.anchor.x, data.anchor.y)
                cairo_rotate(cr, data.angle.radians)
                cairo_translate(cr, -data.anchor.x, -data.anchor.y)
            case .projection, .rotation3D:
                Self.unsupported("3D transform")
            }
            draw(list)
        case .compositingGroup:
            cairo_push_group(cr)
            draw(list)
            cairo_pop_group_to_source(cr)
            cairo_paint(cr)
        case .identity, .geometryGroup, .properties, .accessibility, .state, .archive, .backdropGroup:
            draw(list)
        case .blendMode:
            Self.unsupported("blend mode")
            draw(list)
        case .filter:
            Self.unsupported("filter")
            draw(list)
        default:
            Self.unsupported("effect \(effect)")
            draw(list)
        }
    }

    // MARK: Paths

    /// Appends `path` to the current Cairo path. Returns false when there is nothing to fill.
    private func addPath(_ path: Path) -> Bool {
        switch path.storage {
        case .empty:
            return false
        case let .rect(rect):
            cairo_rectangle(cr, rect.minX, rect.minY, rect.width, rect.height)
        case let .ellipse(rect):
            guard rect.width > 0, rect.height > 0 else { return false }
            cairo_save(cr)
            cairo_translate(cr, rect.midX, rect.midY)
            cairo_scale(cr, rect.width / 2, rect.height / 2)
            cairo_new_sub_path(cr)
            cairo_arc(cr, 0, 0, 1, 0, 2 * .pi)
            cairo_close_path(cr)
            cairo_restore(cr)
        case let .roundedRect(rounded):
            // Continuous corners are drawn as circular arcs.
            addRoundedRect(rounded.rect, cornerSize: rounded.cornerSize)
        default:
            // Path element iteration, stroking and trimming are unimplemented in
            // OpenSwiftUICore off Darwin (Path.forEach, Path.strokedPath).
            Self.unsupported("arbitrary path")
            return false
        }
        return true
    }

    private func addRoundedRect(_ rect: CGRect, cornerSize: CGSize) {
        let rx = min(cornerSize.width, rect.width / 2)
        let ry = min(cornerSize.height, rect.height / 2)
        guard rx > 0, ry > 0 else {
            cairo_rectangle(cr, rect.minX, rect.minY, rect.width, rect.height)
            return
        }
        func corner(_ cx: CGFloat, _ cy: CGFloat, _ start: Double) {
            cairo_save(cr)
            cairo_translate(cr, cx, cy)
            cairo_scale(cr, rx, ry)
            cairo_arc(cr, 0, 0, 1, start, start + .pi / 2)
            cairo_restore(cr)
        }
        cairo_new_sub_path(cr)
        corner(rect.maxX - rx, rect.minY + ry, -.pi / 2)
        corner(rect.maxX - rx, rect.maxY - ry, 0)
        corner(rect.minX + rx, rect.maxY - ry, .pi / 2)
        corner(rect.minX + rx, rect.minY + ry, .pi)
        cairo_close_path(cr)
    }

    // MARK: Paint

    private func setSource(_ color: Color.Resolved) {
        cairo_set_source_rgba(cr, Double(color.red), Double(color.green), Double(color.blue), Double(color.opacity))
    }

    /// Returns false when the paint kind cannot be drawn.
    private func setSource(_ paint: AnyResolvedPaint, bounds: CGRect) -> Bool {
        var visitor = PaintVisitor()
        paint.visit(&visitor)
        switch visitor.paint {
        case let .color(color):
            setSource(color)
        case let .linearGradient(gradient, start, end):
            let pattern = cairo_pattern_create_linear(
                bounds.minX + start.x * bounds.width, bounds.minY + start.y * bounds.height,
                bounds.minX + end.x * bounds.width, bounds.minY + end.y * bounds.height
            )
            for stop in gradient.stops {
                cairo_pattern_add_color_stop_rgba(
                    pattern, stop.location,
                    Double(stop.color.red), Double(stop.color.green), Double(stop.color.blue), Double(stop.color.opacity)
                )
            }
            cairo_set_source(cr, pattern)
            cairo_pattern_destroy(pattern)
        case nil:
            Self.unsupported("paint \(paint)")
            return false
        }
        return true
    }

    // MARK: Diagnostics

    private nonisolated(unsafe) static var warned = Set<String>()

    static func unsupported(_ description: String) {
        guard warned.insert(description).inserted else { return }
        FileHandle.standardError.write(Data("OpenSwiftUIGTK: unsupported \(description)\n".utf8))
    }
}

/// Reads the kind of a resolved paint. Shared with the layer host.
struct PaintVisitor: ResolvedPaintVisitor {
    enum Paint {
        case color(Color.Resolved)
        case linearGradient(ResolvedGradient, UnitPoint, UnitPoint)
    }

    var paint: Paint?

    mutating func visitPaint<P>(_ paint: P) where P: ResolvedPaint {
        if let color = paint as? Color.Resolved {
            self.paint = .color(color)
        } else if let linear = paint as? LinearGradient._Paint {
            self.paint = .linearGradient(linear.gradient, linear.startPoint, linear.endPoint)
        }
    }
}
#endif
