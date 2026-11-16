import AppKit
import ImageIO

/// One framing rule for every sprite source (PokéAPI PNG, Black/White GIF, Showdown GIF, Mega PNG/GIF).
///
/// Sources pad their canvases differently, so aspect-fitting a raw canvas into a box draws the same
/// Pokémon at different sizes. Each sprite is cropped once, at load, to the opaque box that covers all
/// of its frames. The caches hold the cropped result, so no draw path repeats the work.
enum SpriteFrame {
    /// Pixels at or below this alpha count as empty (GIF edges, faint PNG shadows).
    static let alphaThreshold: UInt8 = 16

    /// Smallest rectangle (pixel space, top-left origin) holding every opaque pixel of `images`,
    /// or nil when none has one. Frames without an opaque pixel do not affect the union.
    static func opaqueBounds(of images: [CGImage]) -> CGRect? {
        var union: CGRect?
        for image in images {
            guard let box = opaqueBounds(of: image) else { continue }
            union = union.map { $0.union(box) } ?? box
        }
        return union
    }

    static func opaqueBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Every frame redrawn into the same tight box, so the frames of an animation keep one size and
    /// the sprite does not jitter. A sprite with no opaque pixel comes back unchanged.
    static func cropped(_ images: [CGImage]) -> [CGImage] {
        guard let box = opaqueBounds(of: images) else { return images }
        let width = Int(box.width), height = Int(box.height)
        return images.map { image in
            // Tight canvases (most GIFs) need no redraw.
            if box.minX == 0, box.minY == 0, image.width == width, image.height == height { return image }
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return image }
            context.interpolationQuality = .none
            // Core Graphics counts rows from the bottom; `box` counts from the top.
            context.draw(image, in: CGRect(x: -box.minX, y: box.maxY - CGFloat(image.height),
                                           width: CGFloat(image.width), height: CGFloat(image.height)))
            return context.makeImage() ?? image
        }
    }

    /// A PNG or GIF decoded with the crop applied (a PNG is one frame). Nil when the data is not an image.
    static func decode(_ data: Data) -> [(image: NSImage, delay: TimeInterval)]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let decoded = (0..<CGImageSourceGetCount(source)).compactMap { index in
            CGImageSourceCreateImageAtIndex(source, index, nil).map { (index, $0) }
        }
        guard !decoded.isEmpty else { return nil }
        return zip(cropped(decoded.map(\.1)), decoded.map(\.0)).map { cg, index in
            (NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)),
             GIFDecoder.delay(source, index))
        }
    }

    /// What a still view of this file draws: its first frame, cropped to the union of all frames.
    static func decodeStill(_ data: Data) -> NSImage? { decode(data)?.first?.image }
}
