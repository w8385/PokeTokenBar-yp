import AppKit
import XCTest
@testable import PokeTokenBar

extension XCTestCase {
    /// Shows `image` for the sprite file at `key` until the test ends.
    @MainActor func pinSprite(_ image: NSImage, at key: NSString) {
        SpriteLoader.pinnedImages[key] = image
        addTeardownBlock { @MainActor in SpriteLoader.pinnedImages[key] = nil }
    }
}

final class PinnedSpriteGuardTests: XCTestCase {
    func testNoTestSeedsTheEvictableSpriteCache() throws {
        let tests = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
        // Built from pieces so this file does not match its own scan.
        let needle = "imageCache" + ".setObject"
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains(needle) { offenders.append(url.lastPathComponent) }
        }
        XCTAssertTrue(offenders.isEmpty, """
            NSCache may drop a seeded sprite before the view draws it, so the test sees the real sprite. \
            Use pinSprite(_:at:) instead: \(offenders.joined(separator: ", "))
            """)
    }

    @MainActor func testAPinnedSpriteSurvivesACacheEviction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pin-\(UUID())")
        let key = directory.appendingPathComponent(
            SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false) + ".png").path as NSString
        let image = NSImage(size: NSSize(width: 4, height: 4))
        pinSprite(image, at: key)
        SpriteLoader.imageCache.removeAllObjects()
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 25, directory: directory) === image)
    }
}
