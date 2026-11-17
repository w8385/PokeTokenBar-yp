import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

@MainActor
final class SpriteFrameTests: XCTestCase {
    /// A canvas with one opaque rectangle; `rect` is measured from the top-left like pixel rows.
    private func canvas(_ width: Int, _ height: Int, filling rect: CGRect? = nil,
                        color: NSColor = .red) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if let rect {
            context.setFillColor(try XCTUnwrap(color.usingColorSpace(.deviceRGB)).cgColor)
            context.fill(CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func png(_ image: CGImage) throws -> Data {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private func gif(_ images: [CGImage]) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString,
                                                                         images.count, nil))
        for image in images {
            CGImageDestinationAddImage(destination, image,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sprite-frame-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Opaque rows of a rendered SwiftUI view: (height, rows between the lowest opaque row and the bottom).
    private func opaqueRows(of view: some View) throws -> (height: Int, bottomGap: Int) {
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view).cgImage))
        var top = Int.max, bottom = -1
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.07 {
            top = min(top, y); bottom = max(bottom, y)
        } }
        XCTAssertGreaterThanOrEqual(bottom, 0, "nothing was drawn")
        return (bottom - top + 1, bitmap.pixelsHigh - 1 - bottom)
    }

    func testBoundsOfAPaddedGIFAreTheUnionOverAllFrames() throws {
        let frames = [try canvas(80, 60, filling: CGRect(x: 10, y: 20, width: 12, height: 8)),
                      try canvas(80, 60, filling: CGRect(x: 40, y: 30, width: 6, height: 18))]
        let bounds = try XCTUnwrap(SpriteFrame.opaqueBounds(of: frames))
        XCTAssertEqual(bounds, CGRect(x: 10, y: 20, width: 36, height: 28))
        let cropped = SpriteFrame.cropped(frames)
        XCTAssertEqual(cropped.map { [$0.width, $0.height] }, [[36, 28], [36, 28]])
        let decoded = try XCTUnwrap(SpriteFrame.decode(try gif(frames)))
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.map(\.image.size), [NSSize(width: 36, height: 28), NSSize(width: 36, height: 28)])
    }

    func testCropKeepsThePixelsInPlace() throws {
        let frame = try canvas(50, 40, filling: CGRect(x: 20, y: 10, width: 10, height: 6))
        let cropped = try XCTUnwrap(SpriteFrame.cropped([frame]).first)
        XCTAssertEqual(SpriteFrame.opaqueBounds(of: cropped), CGRect(x: 0, y: 0, width: 10, height: 6),
                       "the crop is exactly the opaque box, nothing else")
    }

    func testAFullyTransparentFrameDoesNotBreakTheUnion() throws {
        let content = try canvas(40, 40, filling: CGRect(x: 5, y: 8, width: 20, height: 24))
        let empty = try canvas(40, 40)
        let cropped = SpriteFrame.cropped([empty, content, empty])
        XCTAssertEqual(cropped.map { [$0.width, $0.height] }, [[20, 24], [20, 24], [20, 24]])
        XCTAssertNil(SpriteFrame.opaqueBounds(of: empty))
    }

    func testASpriteWithNoOpaquePixelIsLeftUncropped() throws {
        let empty = try canvas(40, 30)
        let cropped = SpriteFrame.cropped([empty, empty])
        XCTAssertEqual(cropped.map { [$0.width, $0.height] }, [[40, 30], [40, 30]])
    }

    func testStaticAndAnimatedOfOneSpeciesDrawAtTheSameHeight() throws {
        // Same subject, different canvases and pixel scale: a 96px PNG with padding and a smaller GIF
        // whose frames are drawn at half the PNG's resolution.
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try png(try canvas(96, 96, filling: CGRect(x: 20, y: 14, width: 40, height: 64)))
            .write(to: directory.appendingPathComponent("25-s.png"))
        try gif([try canvas(60, 50, filling: CGRect(x: 4, y: 10, width: 20, height: 32)),
                 try canvas(60, 50, filling: CGRect(x: 4, y: 10, width: 20, height: 32), color: .green)])
            .write(to: directory.appendingPathComponent("25-a.gif"))
        let store = SpriteStore(directory: directory)
        let still = try opaqueRows(of: SpriteView(speciesID: 25, size: 80, spriteStore: store))
        let moving = try opaqueRows(of: SpriteView(speciesID: 25, size: 80, animated: true, spriteStore: store))
        XCTAssertEqual(Double(still.height), Double(moving.height), accuracy: 1)
        XCTAssertEqual(still.bottomGap, moving.bottomGap, "both sit on the same ground line")
    }

    private func wideGIFFixture(withStatic hasStatic: Bool) throws -> SpriteStore {
        let directory = try fixtureDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        if hasStatic {
            try png(try canvas(96, 96, filling: CGRect(x: 20, y: 10, width: 50, height: 60)))
                .write(to: directory.appendingPathComponent("25-s.png"))
        }
        // Frame 0 flares out to the full width; the body of the other frames is narrow and centered.
        try gif([try canvas(100, 40, filling: CGRect(x: 5, y: 5, width: 90, height: 30)),
                 try canvas(100, 40, filling: CGRect(x: 30, y: 5, width: 40, height: 30), color: .green),
                 try canvas(100, 40, filling: CGRect(x: 30, y: 5, width: 40, height: 30))])
            .write(to: directory.appendingPathComponent("25-a.gif"))
        return SpriteStore(directory: directory)
    }

    func testAWidePoseDrawsTallerThanItsPlainFitAndIsCutAtItsSlot() throws {
        let scaled = SpriteView(speciesID: 25, size: 80, animated: true,
                                spriteStore: try wideGIFFixture(withStatic: true))
        let plain = SpriteView(speciesID: 25, size: 80, animated: true,
                               spriteStore: try wideGIFFixture(withStatic: false))
        let scaledRows = try opaqueRows(of: scaled)
        let plainRows = try opaqueRows(of: plain)
        XCTAssertEqual(Double(plainRows.height), 80 * 0.96 * 30 / 90, accuracy: 1)
        XCTAssertEqual(Double(scaledRows.height), Double(plainRows.height) * 1.4, accuracy: 1)

        let roomy = scaled.frame(width: 140, height: 80)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: roomy).cgImage))
        let middle = bitmap.pixelsHigh - 1 - scaledRows.bottomGap - scaledRows.height / 2
        let columns = (0..<bitmap.pixelsWide).filter { (bitmap.colorAt(x: $0, y: middle)?.alphaComponent ?? 0) > 0.07 }
        XCTAssertEqual(columns.count, 80, "the 96pt-wide pose is cut at its 80pt slot even where there is room")
    }

    func testAWideUnionWithANarrowBodyStandsWithin15PercentOfItsStatic() throws {
        // Static 89x82. GIF union 161x107 (one frame flares out); the body is 100 wide, 93 of the 107 rows, centered.
        let directory = try fixtureDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try png(try canvas(96, 96, filling: CGRect(x: 3, y: 7, width: 89, height: 82)))
            .write(to: directory.appendingPathComponent("25-s.png"))
        try gif([try canvas(170, 110, filling: CGRect(x: 30, y: 15, width: 100, height: 93)),
                 try canvas(170, 110, filling: CGRect(x: 4, y: 1, width: 161, height: 107), color: .green),
                 try canvas(170, 110, filling: CGRect(x: 30, y: 15, width: 100, height: 93))])
            .write(to: directory.appendingPathComponent("25-a.gif"))
        let store = SpriteStore(directory: directory)
        let still = try opaqueRows(of: SpriteView(speciesID: 25, size: 76, spriteStore: store))
        let moving = try opaqueRows(of: SpriteView(speciesID: 25, size: 76, animated: true, spriteStore: store))
        XCTAssertEqual(Double(moving.height), Double(still.height), accuracy: Double(still.height) * 0.15,
                       "frame 0 is \(moving.height)pt against a static of \(still.height)pt")
    }

    func testABodyAsWideAsItsUnionIsNotScaledUpPastTheSlot() throws {
        let directory = try fixtureDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try png(try canvas(96, 96, filling: CGRect(x: 3, y: 7, width: 89, height: 82)))
            .write(to: directory.appendingPathComponent("25-s.png"))
        try gif([try canvas(170, 110, filling: CGRect(x: 4, y: 15, width: 161, height: 93)),
                 try canvas(170, 110, filling: CGRect(x: 4, y: 1, width: 161, height: 107), color: .green)])
            .write(to: directory.appendingPathComponent("25-a.gif"))
        let store = SpriteStore(directory: directory)
        let moving = try opaqueRows(of: SpriteView(speciesID: 25, size: 76, animated: true, spriteStore: store))
        XCTAssertEqual(Double(moving.height), 76 * 0.96 * 93 / 161, accuracy: 1.5, "the plain fit, not the 1.4x scale-up")
    }

    func testEveryShapeStandsOnTheBottomOfItsBox() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 1: tall, 2: wide, 3: padded square — three different canvases.
        try png(try canvas(96, 96, filling: CGRect(x: 40, y: 4, width: 16, height: 60)))
            .write(to: directory.appendingPathComponent("1-s.png"))
        try png(try canvas(96, 96, filling: CGRect(x: 4, y: 40, width: 88, height: 20)))
            .write(to: directory.appendingPathComponent("2-s.png"))
        try png(try canvas(96, 96, filling: CGRect(x: 30, y: 30, width: 36, height: 36)))
            .write(to: directory.appendingPathComponent("3-s.png"))
        let store = SpriteStore(directory: directory)
        let gaps = try [1, 2, 3].map { try opaqueRows(of: SpriteView(speciesID: $0, size: 80, spriteStore: store)).bottomGap }
        XCTAssertEqual(Set(gaps).count, 1, "bottom gaps differ: \(gaps)")
        XCTAssertLessThanOrEqual(gaps[0], 3, "the sprite stands on the box bottom, not in the middle")
    }
}
