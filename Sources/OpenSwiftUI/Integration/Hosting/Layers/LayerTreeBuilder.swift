//
//  LayerTreeBuilder.swift
//  OpenSwiftUI
//
//  Turns an OpenSwiftUI display list into a tree of layers for a compositor to draw, and keeps
//  that tree up to date: a display list item keeps its layer from one frame to the next, and
//  only what changed is sent.
//
//  Shown: colours; rectangles, rounded rectangles, circles and capsules filled with a colour
//  or a linear gradient; text; opacity; rectangular and rounded clips; affine transforms and
//  rotations.
//
//  Not shown: arbitrary paths and true ellipses (drawn as capsules), masks, shadows, blurs,
//  images, 3D transforms. Opacity applies to each layer of a group on its own, and a rounded
//  clip only rounds the clipping layer's own content: both are the compositor's limits.

#if OPENSWIFTUI_LAYERS
import CGtk
import Foundation
import LayerKit
@_spi(ForOpenSwiftUIOnly) import OpenSwiftUICore

final class LayerTreeBuilder {
    /// A display list item's identity, and which of the items sharing it this is.
    private struct Key: Hashable {
        var identity: UInt32
        var occurrence: Int
    }

    private final class Entry {
        let layer = CALayer()
        /// What the layer's contents were drawn from, so they are drawn again only on change.
        var text: (version: DisplayList.Version, size: CGSize)?
        var gradient: GradientKey?

        init() {
            // Display list positions are top-left corners.
            layer.anchorPoint = .zero
        }
    }

    private struct GradientKey: Hashable {
        var stops: [Float]
        var start: UnitPoint
        var end: UnitPoint
        /// Width over height, in sixteenths: the gradient's direction depends on it.
        var aspect: Int
    }

    private let root: CALayer
    private let scale: CGFloat
    private var entries: [Key: Entry] = [:]
    private var used: Set<Key> = []
    private var occurrences: [UInt32: Int] = [:]
    private var gradients: [GradientKey: CGImage] = [:]

    init(root: CALayer, scale: CGFloat) {
        self.root = root
        self.scale = scale
    }

    /// Makes the layer tree show `list`.
    func update(_ list: DisplayList) {
        CATransaction.begin()
        // The app already animates: every frame's values are final.
        CATransaction.setDisableActions(true)
        used.removeAll(keepingCapacity: true)
        occurrences.removeAll(keepingCapacity: true)
        setSublayers(of: root, to: layers(for: list))
        entries = entries.filter { used.contains($0.key) }
        CATransaction.commit()
    }

    // MARK: Tree

    private func entry(for item: DisplayList.Item) -> Entry {
        let identity = item.identity.value
        let occurrence = occurrences[identity, default: 0]
        occurrences[identity] = occurrence + 1
        let key = Key(identity: identity, occurrence: occurrence)
        used.insert(key)
        if let entry = entries[key] {
            return entry
        }
        let entry = Entry()
        entries[key] = entry
        return entry
    }

    private func setSublayers(of layer: CALayer, to sublayers: [CALayer]) {
        let current = layer.sublayers ?? []
        if !current.elementsEqual(sublayers, by: ===) {
            layer.sublayers = sublayers
        }
    }

    private func layers(for list: DisplayList) -> [CALayer] {
        var result: [CALayer] = []
        for item in list.items {
            switch item.value {
            case .empty:
                break
            case let .content(content):
                if let layer = contentLayer(content, item: item) {
                    result.append(layer)
                }
            case let .effect(effect, list):
                result.append(contentsOf: effectLayers(effect, list, item: item))
            case let .states(states):
                for (_, list) in states {
                    result.append(contentsOf: layers(for: list))
                }
            }
        }
        return result
    }

    /// Every property the builder ever sets, each given once, so a layer that an item takes
    /// over from another keeps nothing of its past.
    private func configure(
        _ entry: Entry,
        bounds: CGRect,
        position: CGPoint,
        background: CGColor? = nil,
        cornerRadius: CGFloat = 0,
        clips: Bool = false,
        opacity: Float = 1,
        transform: LayerKit.CGAffineTransform = .identity,
        contents: CGImage? = nil,
        contentsScale: CGFloat = 1
    ) {
        let layer = entry.layer
        layer.bounds = bounds
        layer.position = position
        layer.backgroundColor = background
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = clips
        layer.opacity = opacity
        layer.setAffineTransform(transform)
        layer.contentsScale = contentsScale
        layer.contents = contents
        if contents == nil {
            entry.text = nil
            entry.gradient = nil
        }
    }

    // MARK: Content

    private func contentLayer(_ content: DisplayList.Content, item: DisplayList.Item) -> CALayer? {
        let frame = item.frame
        switch content.value {
        case let .color(color):
            let entry = entry(for: item)
            configure(entry, bounds: CGRect(origin: .zero, size: frame.size), position: frame.origin, background: cgColor(color))
            setSublayers(of: entry.layer, to: [])
            return entry.layer
        case let .shape(path, paint, _):
            return shapeLayer(path, paint, item: item)
        case let .text(view, size):
            return textLayer(view, size: size, item: item)
        case let .flattened(list, offset, _):
            let entry = entry(for: item)
            configure(entry, bounds: .zero, position: CGPoint(x: frame.minX + offset.x, y: frame.minY + offset.y))
            setSublayers(of: entry.layer, to: layers(for: list))
            return entry.layer
        case .shadow:
            CairoDisplayListRenderer.unsupported("shadow content in layers")
        case .image:
            CairoDisplayListRenderer.unsupported("image content in layers")
        default:
            CairoDisplayListRenderer.unsupported("content \(content.value) in layers")
        }
        return nil
    }

    private func shapeLayer(_ path: Path, _ paint: AnyResolvedPaint, item: DisplayList.Item) -> CALayer? {
        let rect: CGRect
        let radius: CGFloat
        switch path.storage {
        case .empty:
            return nil
        case let .rect(pathRect):
            (rect, radius) = (pathRect, 0)
        case let .roundedRect(rounded):
            // One radius per layer: an elliptical corner is drawn circular.
            (rect, radius) = (rounded.rect, min(rounded.cornerSize.width, rounded.cornerSize.height))
        case let .ellipse(pathRect):
            // A circle is exact; another ellipse comes out as a capsule.
            (rect, radius) = (pathRect, min(pathRect.width, pathRect.height) / 2)
        default:
            CairoDisplayListRenderer.unsupported("arbitrary path in layers")
            return nil
        }
        var visitor = PaintVisitor()
        paint.visit(&visitor)
        let entry = entry(for: item)
        let position = CGPoint(x: item.frame.minX + rect.minX, y: item.frame.minY + rect.minY)
        let bounds = CGRect(origin: .zero, size: rect.size)
        let cornerRadius = min(radius, min(rect.width, rect.height) / 2)
        switch visitor.paint {
        case let .color(color):
            configure(entry, bounds: bounds, position: position, background: cgColor(color), cornerRadius: cornerRadius)
        case let .linearGradient(gradient, start, end):
            let key = GradientKey(
                stops: gradient.stops.flatMap { [Float($0.location), $0.color.red, $0.color.green, $0.color.blue, $0.color.opacity] },
                start: start,
                end: end,
                aspect: rect.height > 0 ? Int((rect.width / rect.height * 16).rounded()) : 0
            )
            let image = entry.gradient == key ? entry.layer.contents as? CGImage : gradientImage(key)
            // The image is stretched over the layer; the clip rounds it.
            configure(entry, bounds: bounds, position: position, cornerRadius: cornerRadius, clips: true, contents: image)
            entry.gradient = key
            entry.text = nil
        case nil:
            CairoDisplayListRenderer.unsupported("paint \(paint) in layers")
            return nil
        }
        setSublayers(of: entry.layer, to: [])
        return entry.layer
    }

    private func cgColor(_ color: Color.Resolved) -> CGColor {
        CGColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(color.opacity))
    }

    /// A small picture of the gradient, to be stretched over the shape.
    private func gradientImage(_ key: GradientKey) -> CGImage? {
        if let image = gradients[key] {
            return image
        }
        let side = 64
        let aspect = key.aspect > 0 ? Double(key.aspect) / 16 : 1
        // In points of a shape `aspect` wide and 1 high, where the gradient's lines of equal
        // colour are perpendicular to its direction.
        let startX = Double(key.start.x) * aspect, startY = Double(key.start.y)
        let deltaX = Double(key.end.x) * aspect - startX, deltaY = Double(key.end.y) - startY
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        let stops = stride(from: 0, to: key.stops.count, by: 5).map { Array(key.stops[$0 ..< $0 + 5]) }
        guard let first = stops.first, let last = stops.last else { return nil }
        func colour(at location: Float) -> [Float] {
            if location <= first[0] { return first }
            for (lower, upper) in zip(stops, stops.dropFirst()) where location <= upper[0] {
                let span = upper[0] - lower[0]
                let fraction = span > 0 ? (location - lower[0]) / span : 1
                return zip(lower, upper).map { $0 + ($1 - $0) * fraction }
            }
            return last
        }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let pointX = (Double(x) + 0.5) / Double(side) * aspect, pointY = (Double(y) + 0.5) / Double(side)
                let along = lengthSquared > 0
                    ? ((pointX - startX) * deltaX + (pointY - startY) * deltaY) / lengthSquared : 0
                let stop = colour(at: Float(min(max(along, 0), 1)))
                let alpha = stop[4]
                func byte(_ component: Float) -> UInt8 { UInt8((min(max(component * alpha, 0), 1) * 255).rounded()) }
                let offset = (y * side + x) * 4
                // BGRA, premultiplied.
                pixels[offset] = byte(stop[3])
                pixels[offset + 1] = byte(stop[2])
                pixels[offset + 2] = byte(stop[1])
                pixels[offset + 3] = UInt8((min(max(alpha, 0), 1) * 255).rounded())
            }
        }
        let image = pixels.withUnsafeBytes {
            CGImage(bgraPremultiplied: $0, width: side, height: side, bytesPerRow: side * 4)
        }
        // A shape that changes proportions asks for a new picture every frame.
        if gradients.count >= 64 {
            gradients.removeAll()
        }
        gradients[key] = image
        return image
    }

    /// Text is drawn here, with Pango, into a picture the compositor shows.
    private func textLayer(_ view: StyledTextContentView, size: CGSize, item: DisplayList.Item) -> CALayer? {
        // Room for ink that leaves the text's own rectangle, such as an italic's overhang.
        let margin: CGFloat = 2
        let pixelWidth = Int(((size.width + 2 * margin) * scale).rounded(.up))
        let pixelHeight = Int(((size.height + 2 * margin) * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0, size.width > 0, size.height > 0 else { return nil }
        let entry = entry(for: item)
        var image = entry.layer.contents as? CGImage
        if image == nil || entry.text?.version != item.version || entry.text?.size != size {
            guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(pixelWidth), Int32(pixelHeight)),
                  cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS,
                  let cr = cairo_create(surface) else {
                return nil
            }
            cairo_scale(cr, Double(scale), Double(scale))
            PangoTextLayout.draw(view, size: size, origin: CGPoint(x: margin, y: margin), in: cr)
            cairo_destroy(cr)
            cairo_surface_flush(surface)
            let stride = Int(cairo_image_surface_get_stride(surface))
            if let data = cairo_image_surface_get_data(surface) {
                image = CGImage(
                    bgraPremultiplied: UnsafeRawBufferPointer(start: data, count: stride * pixelHeight),
                    width: pixelWidth, height: pixelHeight, bytesPerRow: stride
                )
            }
            cairo_surface_destroy(surface)
        }
        configure(
            entry,
            bounds: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale),
            position: CGPoint(x: item.frame.minX - margin, y: item.frame.minY - margin),
            contents: image,
            contentsScale: scale
        )
        entry.text = (item.version, size)
        entry.gradient = nil
        setSublayers(of: entry.layer, to: [])
        return entry.layer
    }

    // MARK: Effects

    /// The layers for an effect over `list`, whose items are placed from the effect item's
    /// position.
    private func effectLayers(_ effect: DisplayList.Effect, _ list: DisplayList, item: DisplayList.Item) -> [CALayer] {
        let position = item.position
        var bounds = CGRect.zero
        var origin = position
        var cornerRadius: CGFloat = 0
        var clips = false
        var opacity: Float = 1
        var transform = LayerKit.CGAffineTransform.identity
        switch effect {
        case let .opacity(alpha):
            opacity = alpha
        case let .clip(path, _, _):
            switch path.storage {
            case let .rect(rect):
                (bounds, clips) = (rect, true)
            case let .roundedRect(rounded):
                (bounds, clips) = (rounded.rect, true)
                cornerRadius = min(rounded.cornerSize.width, rounded.cornerSize.height)
            default:
                CairoDisplayListRenderer.unsupported("clip to an arbitrary path in layers")
            }
            // The layer's own coordinates start at the clip's corner, so the items keep theirs.
            origin = CGPoint(x: position.x + bounds.minX, y: position.y + bounds.minY)
        case let .transform(.affine(affine)):
            transform = LayerKit.CGAffineTransform(a: affine.a, b: affine.b, c: affine.c, d: affine.d, tx: affine.tx, ty: affine.ty)
        case let .transform(.rotation(data)):
            transform = LayerKit.CGAffineTransform(translationX: -data.anchor.x, y: -data.anchor.y)
                .concatenating(LayerKit.CGAffineTransform(rotationAngle: CGFloat(data.angle.radians)))
                .concatenating(LayerKit.CGAffineTransform(translationX: data.anchor.x, y: data.anchor.y))
        case .transform:
            CairoDisplayListRenderer.unsupported("3D transform in layers")
        case .mask:
            CairoDisplayListRenderer.unsupported("mask in layers")
        case .blendMode:
            CairoDisplayListRenderer.unsupported("blend mode in layers")
        case .filter:
            CairoDisplayListRenderer.unsupported("filter in layers")
        default:
            // Groups and bookkeeping effects change nothing that is drawn. One that also
            // moves nothing needs no layer of its own.
            if position == .zero {
                return layers(for: list)
            }
        }
        let entry = entry(for: item)
        configure(
            entry, bounds: bounds, position: origin,
            cornerRadius: cornerRadius, clips: clips, opacity: opacity, transform: transform
        )
        setSublayers(of: entry.layer, to: layers(for: list))
        return [entry.layer]
    }
}
#endif
