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
    /// A display list item's identity, and which of the items sharing it this is. Items
    /// without an identity are told apart by where they are: `scope` is the item around them
    /// that has a layer, so that one more of them somewhere leaves the others their layers.
    private struct Key: Hashable {
        var identity: UInt32
        var occurrence: Int
        var scope: Int
    }

    private final class Entry {
        let key: Key
        let layer: CALayer
        /// What the layer's contents were drawn from, so they are drawn again only on change.
        var text: (seed: DisplayList.Seed, size: CGSize)?
        var gradient: GradientKey?
        /// For a scroll layer: what the compositor was last told, and who hears where it
        /// has scrolled to.
        var scrolling: (contentSize: CGSize, axes: Axis.Set)?
        var scrollHandle: CompositorScrollHandle?
        /// The animations the compositor is running for this layer, by the seed of their
        /// description; see `AnimationSamples`. While one runs, the property is the
        /// compositor's and what the app samples for it is ignored. For the position, also
        /// how far the layer was from the item's origin when the animation was made.
        var position: (seed: UInt32, gap: CGSize)?
        var opacitySeed: UInt32?
        var transformSeed: UInt32?

        init(key: Key, layer: CALayer) {
            self.key = key
            self.layer = layer
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
    /// How many items have had each key so far in this update, whatever their occurrence.
    private var occurrences: [Key: Int] = [:]
    /// The key of the item whose layer the items now being walked go into; 0 at the root.
    private var scope = 0
    /// The engine's time for the display list being shown.
    private var now = Time.zero
    private var gradients: [GradientKey: CGImage] = [:]

    init(root: CALayer, scale: CGFloat) {
        self.root = root
        self.scale = scale
    }

    /// Makes the layer tree show `list`, which is the engine's picture at `time`.
    func update(_ list: DisplayList, time: Time) {
        CATransaction.begin()
        // Nothing animates by being set: what the compositor is to animate is said in full.
        CATransaction.setDisableActions(true)
        now = time
        used.removeAll(keepingCapacity: true)
        occurrences.removeAll(keepingCapacity: true)
        scope = 0
        setSublayers(of: root, to: layers(for: list))
        entries = entries.filter { used.contains($0.key) }
        CATransaction.commit()
    }

    // MARK: Tree

    /// The layer kept for `item`: a scroll layer when `scrolls`, a plain one otherwise.
    private func entry(for item: DisplayList.Item, scrolls: Bool = false) -> Entry {
        let identity = item.identity.value
        var key = Key(identity: identity, occurrence: 0, scope: identity == 0 ? scope : 0)
        let occurrence = occurrences[key, default: 0]
        occurrences[key] = occurrence + 1
        key.occurrence = occurrence
        used.insert(key)
        if let entry = entries[key], (entry.layer is CAScrollLayer) == scrolls {
            return entry
        }
        let entry = Entry(key: key, layer: scrolls ? CAScrollLayer() : CALayer())
        entries[key] = entry
        return entry
    }

    /// The layers for `list`, which is what is inside `entry`'s item.
    private func layers(for list: DisplayList, in entry: Entry) -> [CALayer] {
        let outer = scope
        scope = entry.key.hashValue
        defer { scope = outer }
        return layers(for: list)
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

    /// Which of a layer's properties an effect item's description is about.
    private enum Described {
        case nothing, opacity, transform
    }

    /// Every property the builder ever sets, each given once, so a layer that an item takes
    /// over from another keeps nothing of its past. `ahead` is the description of the
    /// item's animations, if they are to be the compositor's; `origin` is the item origin
    /// that `position` was worked out from, and `effect` says what an effect item's
    /// description is about.
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
        contentsScale: CGFloat = 1,
        ahead: DisplayList.Ahead? = nil,
        origin: CGPoint = .zero,
        effect: Described = .nothing
    ) {
        let layer = entry.layer
        layer.bounds = bounds
        place(entry, at: position, origin: origin, track: ahead?.origin)
        layer.backgroundColor = background
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = clips
        fade(entry, to: opacity, track: effect == .opacity ? ahead?.effect : nil)
        turn(entry, to: transform, track: effect == .transform ? ahead?.effect : nil)
        layer.contentsScale = contentsScale
        layer.contents = contents
        if contents == nil {
            entry.text = nil
            entry.gradient = nil
        }
    }

    // MARK: Animations

    private static let positionKey = "described.position"
    private static let opacityKey = "described.opacity"
    private static let transformKey = "described.transform"

    /// Puts the layer at `position`, or, when its way there is described, has the
    /// compositor take it there.
    private func place(_ entry: Entry, at position: CGPoint, origin: CGPoint, track: DisplayList.Ahead.Track<CGPoint>?) {
        let layer = entry.layer
        guard let track else {
            if entry.position != nil {
                entry.position = nil
                layer.removeAnimation(forKey: Self.positionKey)
            }
            layer.position = position
            return
        }
        // The layer is a fixed distance from the item's origin; should that distance
        // change, the animation is made again for the new one. It is worked back from two
        // sums, so it is the same only to within rounding.
        let gap = CGSize(width: position.x - origin.x, height: position.y - origin.y)
        if let current = entry.position, current.seed == track.seed,
           abs(current.gap.width - gap.width) < 0.001, abs(current.gap.height - gap.height) < 0.001 {
            return
        }
        entry.position = (track.seed, gap)
        let points = track.values().map { CGPoint(x: $0.x + gap.width, y: $0.y + gap.height) }
        layer.position = play(track, points, now: position, on: layer, keyPath: "position", key: Self.positionKey)
    }

    private func fade(_ entry: Entry, to opacity: Float, track: DisplayList.Ahead.Track<DisplayList.Effect>?) {
        let layer = entry.layer
        guard let track else {
            if entry.opacitySeed != nil {
                entry.opacitySeed = nil
                layer.removeAnimation(forKey: Self.opacityKey)
            }
            layer.opacity = opacity
            return
        }
        guard entry.opacitySeed != track.seed else {
            return
        }
        entry.opacitySeed = track.seed
        let opacities = track.values().map { effect -> Float in
            if case let .opacity(value) = effect { value } else { opacity }
        }
        layer.opacity = play(track, opacities, now: opacity, on: layer, keyPath: "opacity", key: Self.opacityKey)
    }

    private func turn(
        _ entry: Entry,
        to transform: LayerKit.CGAffineTransform,
        track: DisplayList.Ahead.Track<DisplayList.Effect>?
    ) {
        let layer = entry.layer
        guard let track else {
            if entry.transformSeed != nil {
                entry.transformSeed = nil
                layer.removeAnimation(forKey: Self.transformKey)
            }
            layer.setAffineTransform(transform)
            return
        }
        guard entry.transformSeed != track.seed else {
            return
        }
        entry.transformSeed = track.seed
        var transforms = track.values().map(layerTransform)
        // The engine gives up on a transform that cannot be undone, such as a scale of
        // nothing, and says "no effect" instead. Among values that all but vanish that is
        // the vanishing one, and the nearest of them stands in for it.
        for index in transforms.indices where transforms[index] == nil {
            let nearest = [index - 1, index + 1].compactMap { transforms.indices.contains($0) ? transforms[$0] : nil }.first
            if let nearest, abs(nearest.a * nearest.d - nearest.b * nearest.c) < 0.05 {
                transforms[index] = nearest
            }
        }
        let final = play(
            track, transforms.map { $0 ?? .identity }, now: transform,
            on: layer, keyPath: "transform", key: Self.transformKey,
            wrap: { CATransform3DMakeAffineTransform($0) }
        )
        layer.setAffineTransform(final)
    }

    /// What an effect does to its layer, when it is a transform a layer can have. Nil for no
    /// effect at all.
    private func layerTransform(_ effect: DisplayList.Effect) -> LayerKit.CGAffineTransform? {
        switch effect {
        case let .transform(.affine(affine)):
            LayerKit.CGAffineTransform(a: affine.a, b: affine.b, c: affine.c, d: affine.d, tx: affine.tx, ty: affine.ty)
        case let .transform(.rotation(data)):
            LayerKit.CGAffineTransform(translationX: -data.anchor.x, y: -data.anchor.y)
                .concatenating(LayerKit.CGAffineTransform(rotationAngle: CGFloat(data.angle.radians)))
                .concatenating(LayerKit.CGAffineTransform(translationX: data.anchor.x, y: data.anchor.y))
        default:
            nil
        }
    }

    /// Has the compositor take a property of `layer` through `values`, the values of
    /// `track`, and returns the value the property is to have underneath. For a movement
    /// that ends that is where it ends, so that nothing moves when the animation is over;
    /// for one that comes round for ever it is `now`, the value at this moment.
    private func play<Value>(
        _ track: DisplayList.Ahead.Track<some Any>,
        _ values: [Value],
        now current: Value,
        on layer: CALayer,
        keyPath: String,
        key: String,
        wrap: (Value) -> Any = { $0 }
    ) -> Value {
        // A description reaches the builder when it is made, or later: an item can come to
        // have a layer in the middle of its animation. Either way it starts from now.
        let elapsed = max(now - track.time, 0)
        var values = values
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        if track.repeats {
            // One round, ending as it begins, begun when the description was made.
            let round = Double(values.count - 1) * track.step
            guard round > 0 else {
                layer.removeAnimation(forKey: key)
                return current
            }
            animation.repeatCount = .infinity
            animation.timeOffset = elapsed.truncatingRemainder(dividingBy: round)
        } else {
            let passed = Int((elapsed / track.step).rounded())
            values.removeFirst(min(passed, max(values.count - 1, 0)))
        }
        guard values.count > 1 else {
            layer.removeAnimation(forKey: key)
            return values.last ?? current
        }
        animation.values = values.map(wrap)
        animation.duration = Double(values.count - 1) * track.step
        animation.calculationMode = .linear
        layer.add(animation, forKey: key)
        return track.repeats ? current : values[values.count - 1]
    }

    // MARK: Content

    private func contentLayer(_ content: DisplayList.Content, item: DisplayList.Item) -> CALayer? {
        let frame = item.frame
        switch content.value {
        case let .color(color):
            let entry = entry(for: item)
            configure(
                entry, bounds: CGRect(origin: .zero, size: frame.size), position: frame.origin,
                background: cgColor(color), ahead: item.ahead, origin: frame.origin
            )
            setSublayers(of: entry.layer, to: [])
            return entry.layer
        case let .shape(path, paint, _):
            return shapeLayer(path, paint, item: item)
        case let .text(view, size):
            return textLayer(view, size: size, seed: content.seed, item: item)
        case let .flattened(list, offset, _):
            let entry = entry(for: item)
            configure(
                entry, bounds: .zero, position: CGPoint(x: frame.minX + offset.x, y: frame.minY + offset.y),
                ahead: item.ahead, origin: frame.origin
            )
            setSublayers(of: entry.layer, to: layers(for: list, in: entry))
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
            configure(
                entry, bounds: bounds, position: position, background: cgColor(color), cornerRadius: cornerRadius,
                ahead: item.ahead, origin: item.position
            )
        case let .linearGradient(gradient, start, end):
            let key = GradientKey(
                stops: gradient.stops.flatMap { [Float($0.location), $0.color.red, $0.color.green, $0.color.blue, $0.color.opacity] },
                start: start,
                end: end,
                aspect: rect.height > 0 ? Int((rect.width / rect.height * 16).rounded()) : 0
            )
            let image = entry.gradient == key ? entry.layer.contents as? CGImage : gradientImage(key)
            // The image is stretched over the layer; the clip rounds it.
            configure(
                entry, bounds: bounds, position: position, cornerRadius: cornerRadius, clips: true, contents: image,
                ahead: item.ahead, origin: item.position
            )
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
    /// `seed` changes when what the text shows does, and not when the text only moves.
    private func textLayer(
        _ view: StyledTextContentView,
        size: CGSize,
        seed: DisplayList.Seed,
        item: DisplayList.Item
    ) -> CALayer? {
        // Room for ink that leaves the text's own rectangle, such as an italic's overhang.
        let margin: CGFloat = 2
        let pixelWidth = Int(((size.width + 2 * margin) * scale).rounded(.up))
        let pixelHeight = Int(((size.height + 2 * margin) * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0, size.width > 0, size.height > 0 else { return nil }
        let entry = entry(for: item)
        var image = entry.layer.contents as? CGImage
        if image == nil || entry.text?.seed != seed || entry.text?.size != size {
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
            contentsScale: scale,
            ahead: item.ahead,
            origin: item.position
        )
        entry.text = (seed, size)
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
        var described = Described.nothing
        var transform = LayerKit.CGAffineTransform.identity
        var ahead = item.ahead
        switch effect {
        case let .opacity(alpha):
            described = .opacity
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
        case .transform(.affine), .transform(.rotation):
            described = .transform
            transform = layerTransform(effect) ?? .identity
        case .transform:
            CairoDisplayListRenderer.unsupported("3D transform in layers")
        case .mask:
            CairoDisplayListRenderer.unsupported("mask in layers")
        case .blendMode:
            CairoDisplayListRenderer.unsupported("blend mode in layers")
        case .filter:
            CairoDisplayListRenderer.unsupported("filter in layers")
        case let .platformGroup(factory) where factory is CompositorScrollGroup:
            if let group = factory as? CompositorScrollGroup {
                return [scrollLayer(group, list, item: item)]
            }
        case let .platformGroup(factory) where factory is CompositorScrollContent:
            // Laid out already scrolled, for layout and hit testing. On screen the scroll
            // layer around it does the scrolling, so the content itself stays put: it is
            // where the compositor has it, whatever the app last knew.
            origin = .zero
            ahead = nil
        default:
            // Groups and bookkeeping effects change nothing that is drawn. One that also
            // moves nothing, now or on its way, needs no layer of its own. A transform being
            // animated keeps its layer at a value the engine gave up on (see `turn`).
            if case .identity = effect, ahead?.effect != nil {
                described = .transform
            } else if position == .zero, ahead?.origin == nil {
                return layers(for: list)
            }
        }
        let entry = entry(for: item)
        configure(
            entry, bounds: bounds, position: origin,
            cornerRadius: cornerRadius, clips: clips, opacity: opacity, transform: transform,
            ahead: ahead, origin: position, effect: described
        )
        setSublayers(of: entry.layer, to: layers(for: list, in: entry))
        return [entry.layer]
    }

    /// A scroll view's viewport: a layer whose content the compositor scrolls under a touch
    /// by itself, telling the scroll view where it has got to.
    private func scrollLayer(_ group: CompositorScrollGroup, _ list: DisplayList, item: DisplayList.Item) -> CALayer {
        let entry = entry(for: item, scrolls: true)
        guard let scroll = entry.layer as? CAScrollLayer else { return entry.layer }
        // A scroll layer keeps its bounds origin, which is the compositor's, whatever is set.
        configure(
            entry, bounds: CGRect(origin: .zero, size: item.size), position: item.position, clips: true,
            ahead: item.ahead, origin: item.position
        )
        if entry.scrolling?.contentSize != group.contentSize || entry.scrolling?.axes != group.axes {
            let horizontal = group.axes.contains(.horizontal), vertical = group.axes.contains(.vertical)
            scroll.scrollMode = horizontal && vertical ? .both
                : horizontal ? .horizontally
                : vertical ? .vertically : .none
            scroll.touchScrolling = CAScrollLayer.TouchScrolling(contentSize: group.contentSize)
            entry.scrolling = (group.contentSize, group.axes)
        }
        if entry.scrollHandle !== group.handle {
            // A new layer starts unscrolled, which the scroll view has to hear: it may be
            // one that has scrolled before, with another layer.
            if entry.scrollHandle == nil {
                group.handle.report(.zero, isAtRest: true)
            }
            entry.scrollHandle = group.handle
            scroll.onScroll = { [weak handle = group.handle] offset, phase in
                handle?.report(CGSize(width: offset.x, height: offset.y), isAtRest: phase == .idle)
            }
        }
        setSublayers(of: scroll, to: layers(for: list, in: entry))
        return scroll
    }
}
#endif
