import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

private struct ColorRenderingProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class DexColorRenderingTests: XCTestCase {
    // Synthetic pixels make the two appearances unambiguous without network or user saves.
    private func solidImage(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 96, height: 96))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        image.unlockFocus()
        return image
    }

    private func withSprites(_ body: () async throws -> Void) async throws {
        let keys = [false, true].map {
            SpriteLoader.cacheDir.appendingPathComponent(
                SpriteStore.cacheKey(speciesID: 606, animated: false, shiny: $0) + ".png").path as NSString
        }
        let previous = keys.map { SpriteLoader.imageCache.object(forKey: $0) }
        for (key, color) in zip(keys, [NSColor.red, NSColor.blue]) {
            SpriteLoader.imageCache.setObject(solidImage(color), forKey: key)
        }
        defer {
            for (key, image) in zip(keys, previous) {
                if let image { SpriteLoader.imageCache.setObject(image, forKey: key) }
                else { SpriteLoader.imageCache.removeObject(forKey: key) }
            }
        }
        try await body()
    }

    private func fixture(shinyLast: Bool) throws -> (CompanionStore, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-color-\(UUID()).json")
        var state = CompanionState()
        state.language = .en
        state.dex = [!shinyLast, shinyLast].enumerated().map { index, shiny in
            DexEntry(baseID: 606, finalID: 606, chainOrder: [606], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                     isShiny: shiny, names: [606: ["en": "Elgyem"]])
        }
        try JSONEncoder().encode(state).write(to: file)
        return (CompanionStore(provider: ColorRenderingProvider(), fileURL: file), file)
    }

    private func fixture(onlyShiny: Bool) throws -> (CompanionStore, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-color-\(UUID()).json")
        var state = CompanionState()
        state.language = .en
        state.dex = [
            DexEntry(baseID: 606, finalID: 606, chainOrder: [606], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                     isShiny: onlyShiny, names: [606: ["en": "Elgyem"]])
        ]
        try JSONEncoder().encode(state).write(to: file)
        return (CompanionStore(provider: ColorRenderingProvider(), fileURL: file), file)
    }

    private func colorRows(_ captured: NSBitmapImageRep, shiny: Bool) -> [Int] {
        // AppKit display caches may use float/extended color formats. Normalize via PNG
        // before reading components, matching the pixels written to the evidence file.
        guard let data = captured.representation(using: .png, properties: [:]),
              let bitmap = NSBitmapImageRep(data: data) else { return [] }
        var rows: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            var matches = 0
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.greenComponent < 0.4,
                   (shiny ? color.blueComponent > 0.8 && color.redComponent < 0.3
                          : color.redComponent > 0.8 && color.blueComponent < 0.3) {
                    matches += 1
                }
            }
            if matches >= 20 { rows.append(y) }
        }
        return rows
    }

    /// Yellow pixels of the ✨ glyph. The synthetic sprites are pure red and blue, and text is gray.
    private func sparklePixels(in captured: NSBitmapImageRep, x: CGFloat, y: CGFloat,
                               width: CGFloat, height: CGFloat) -> Int {
        guard let data = captured.representation(using: .png, properties: [:]),
              let bitmap = NSBitmapImageRep(data: data) else { return 0 }
        var count = 0
        for row in Int(y)..<min(bitmap.pixelsHigh, Int(y + height)) {
            for column in Int(x)..<min(bitmap.pixelsWide, Int(x + width)) {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.85, color.greenComponent > 0.6, color.blueComponent < 0.5 { count += 1 }
            }
        }
        return count
    }

    /// The Box lays individuals out left to right, so the order shows in the columns.
    private func colorColumns(_ captured: NSBitmapImageRep, shiny: Bool) -> [Int] {
        guard let data = captured.representation(using: .png, properties: [:]),
              let bitmap = NSBitmapImageRep(data: data) else { return [] }
        var columns: [Int] = []
        for x in 0..<bitmap.pixelsWide {
            var matches = 0
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.greenComponent < 0.4,
                   (shiny ? color.blueComponent > 0.8 && color.redComponent < 0.3
                          : color.redComponent > 0.8 && color.blueComponent < 0.3) {
                    matches += 1
                }
            }
            if matches >= 20 { columns.append(x) }
        }
        return columns
    }

    /// The selector's header updates synchronously, but SpriteView changes its cached image in
    /// .task(id:), so this waits for those rendered pixels.
    private func waitForDetailSprite(_ host: NSView, shiny: Bool) async throws -> NSBitmapImageRep {
        var bitmap = try OffscreenRender.bitmap(of: host)
        try await OffscreenRender.waitUntil("the detail sprite to turn \(shiny ? "shiny" : "normal")", in: host) {
            bitmap = try OffscreenRender.bitmap(of: host)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let normalized = try XCTUnwrap(NSBitmapImageRep(data: png))
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            // Center of the synthetic 82pt identity sprite, below the appearance picker.
            let pixel = try XCTUnwrap(normalized.colorAt(x: Int(41 * scale), y: Int(101 * scale))?
                .usingColorSpace(.deviceRGB))
            return pixel.greenComponent < 0.4
                && (shiny ? pixel.blueComponent > 0.8 && pixel.redComponent < 0.3
                          : pixel.redComponent > 0.8 && pixel.blueComponent < 0.3)
        }
        return bitmap
    }

    func testDetailSelectorChangesMountedPixelsAndReturnsToNormal() async throws {
        let (store, file) = try fixture(shinyLast: true)
        defer { try? FileManager.default.removeItem(at: file) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detail-colors-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (shiny, color) in zip([false, true], [NSColor.red, NSColor.blue]) {
            let cgImage = try XCTUnwrap(solidImage(color).cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let key = SpriteStore.cacheKey(speciesID: 606, animated: false, shiny: shiny)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(key + ".png"))
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, cgImage, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let animatedKey = SpriteStore.cacheKey(speciesID: 606, animated: true, shiny: shiny)
            try (data as Data).write(to: directory.appendingPathComponent(animatedKey + ".gif"))
        }
        let species = try XCTUnwrap(store.dexSpecies.first)
        let view = PokemonDetailView(store: store, species: species, onBack: {}, selectedShiny: false,
                                     spriteStore: SpriteStore(directory: directory))
            .frame(width: PopoverMetrics.contentWidth, height: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let host = OffscreenRender.host(view, size: CGSize(width: PopoverMetrics.contentWidth, height: 520),
                                        appearance: .aqua)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for (step, shiny) in [false, true, false].enumerated() {
            host.layoutSubtreeIfNeeded()
            let segmented = try XCTUnwrap(descendants(host).compactMap { $0 as? NSSegmentedControl }.first)
            segmented.selectedSegment = shiny ? 1 : 0
            segmented.sendAction(segmented.action, to: segmented.target)
            let bitmap = try await waitForDetailSprite(host, shiny: shiny)
            XCTAssertGreaterThan(colorRows(bitmap, shiny: shiny).count, 40,
                                 "step \(step): selected \(shiny ? "shiny" : "normal") sprite must appear within 5 seconds")
            XCTAssertEqual(colorRows(bitmap, shiny: !shiny).count, 0,
                           "step \(step): selected \(shiny ? "shiny" : "normal") must not retain the previous appearance")
            let scale = CGFloat(bitmap.pixelsWide) / PopoverMetrics.contentWidth
            XCTAssertEqual(species.name, "Elgyem")
            // The shiny badge is "✨ Shiny": count the sparkle's yellow pixels in the header, right of the sprite.
            let sparkle = sparklePixels(in: bitmap, x: 90 * scale, y: 58 * scale,
                                        width: 220 * scale, height: 85 * scale)
            XCTAssertEqual(sparkle > 10, shiny, "badge must follow the displayed individual: \(sparkle) sparkle pixels")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                URL(fileURLWithPath: "/private/tmp/dex-color-detail-\(shiny ? "shiny" : "normal").png"))
        }
    }

    func testBoxRendersEachIndividualsColorInBothAcquisitionOrdersAndOnReentry() async throws {
        try await withSprites {
            for shinyLast in [false, true] {
                let (store, file) = try fixture(shinyLast: shinyLast)
                defer { try? FileManager.default.removeItem(at: file) }
                for visit in 0..<2 {
                    let navigation = PopoverNavigation()
                    let view = BoxView(store: store, navigation: navigation)
                        .frame(width: PopoverMetrics.contentWidth, height: 520)
                        .background(Color.white)
                        .environment(\.colorScheme, .light)
                        .environment(\.locale, store.language.displayLocale)
                    let host = OffscreenRender.host(view, size: CGSize(width: PopoverMetrics.contentWidth, height: 520),
                                                    appearance: .aqua)
                    var bitmap = try OffscreenRender.bitmap(of: host)
                    try await OffscreenRender.waitUntil("both individuals' colors in the Box", in: host) {
                        bitmap = try OffscreenRender.bitmap(of: host)
                        return colorRows(bitmap, shiny: false).count > 20 && colorRows(bitmap, shiny: true).count > 20
                    }
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: "/private/tmp/dex-color-log-shiny-last-\(shinyLast).png"))
                    let normalRows = colorRows(bitmap, shiny: false)
                    let shinyRows = colorRows(bitmap, shiny: true)
                    XCTAssertGreaterThan(normalRows.count, 20, "normal catch must retain normal pixels")
                    XCTAssertGreaterThan(shinyRows.count, 20, "shiny catch must retain shiny pixels")
                    let firstNormal = try XCTUnwrap(colorColumns(bitmap, shiny: false).first)
                    let firstShiny = try XCTUnwrap(colorColumns(bitmap, shiny: true).first)
                    XCTAssertEqual(firstShiny < firstNormal, shinyLast,
                                   "newest catch is the first cell; colors must follow its individual")
                    if visit == 0 {
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                            URL(fileURLWithPath: "/private/tmp/dex-color-log-shiny-last-\(shinyLast).png"))
                    }
                }
            }
        }
    }

    func testPokedexGridRendersShinySpeciesColor() async throws {
        try await withSprites {
            for shiny in [true, false] {
                let (store, file) = try fixture(onlyShiny: shiny)
                defer { try? FileManager.default.removeItem(at: file) }
                let navigation = PopoverNavigation()
                let view = CollectionView(store: store, navigation: navigation)
                    .frame(width: PopoverMetrics.contentWidth, height: 520)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
                    .environment(\.locale, store.language.displayLocale)
                let host = OffscreenRender.host(view, size: CGSize(width: PopoverMetrics.contentWidth, height: 520),
                                                appearance: .aqua)
                var bitmap = try OffscreenRender.bitmap(of: host)
                try await OffscreenRender.waitUntil("the \(shiny ? "shiny" : "normal") color in the Pokédex grid", in: host) {
                    bitmap = try OffscreenRender.bitmap(of: host)
                    return colorRows(bitmap, shiny: shiny).count > 20
                }
                let normalRows = colorRows(bitmap, shiny: false)
                let shinyRows = colorRows(bitmap, shiny: true)
                if shiny {
                    XCTAssertGreaterThan(shinyRows.count, 20, "shiny species must render shiny pixels in Pokédex grid")
                    XCTAssertEqual(normalRows.count, 0, "shiny species must not render normal pixels in Pokédex grid")
                } else {
                    XCTAssertGreaterThan(normalRows.count, 20, "normal species must render normal pixels in Pokédex grid")
                    XCTAssertEqual(shinyRows.count, 0, "normal species must not render shiny pixels in Pokédex grid")
                }
            }
        }
    }
}

