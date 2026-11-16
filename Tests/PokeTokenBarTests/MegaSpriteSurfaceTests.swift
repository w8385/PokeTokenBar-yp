import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

/// Serves tiny PNG/GIF sprites for the PokéAPI sprites host and records every request path.
private final class SpriteStubURLProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        private var png = Data()
        private var gif = Data()
        func configure(png: Data, gif: Data) { lock.withLock { urls = []; self.png = png; self.gif = gif } }
        func receive(_ url: URL) -> (png: Data, gif: Data) { lock.withLock { urls.append(url); return (png, gif) } }
        var requests: [URL] { lock.withLock { urls } }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "raw.githubusercontent.com" && ["png", "gif"].contains(request.url?.pathExtension ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let served = Self.state.receive(url)
        let isGIF = url.pathExtension == "gif"
        // Like upstream: every Mega has a PNG, only the classic ones have a Showdown GIF.
        let id = Int(url.deletingPathExtension().lastPathComponent) ?? 0
        let exists = isGIF ? MegaStone.animatedSpriteIDs.contains(id) : true
        let response = HTTPURLResponse(url: url, statusCode: exists ? 200 : 404, httpVersion: nil,
                                       headerFields: ["Content-Type": isGIF ? "image/gif" : "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if exists { client?.urlProtocol(self, didLoad: isGIF ? served.gif : served.png) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct SpriteFixture {
    let directory: URL

    static func make() throws -> SpriteFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mega-sprite-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func pixels(_ red: CGFloat, _ green: CGFloat) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            return try XCTUnwrap(context.makeImage())
        }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: try pixels(0, 0)).representation(using: .png, properties: [:]))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        for (red, green) in [(CGFloat(1), CGFloat(0)), (CGFloat(0), CGFloat(1))] {
            CGImageDestinationAddImage(destination, try pixels(red, green),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        SpriteStubURLProtocol.state.configure(png: png, gif: data as Data)
        URLProtocol.registerClass(SpriteStubURLProtocol.self)
        return SpriteFixture(directory: directory)
    }

    func tearDown() {
        URLProtocol.unregisterClass(SpriteStubURLProtocol.self)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A held Mega Stone must reach every surface that draws its holder, and a Mega form without an animated
/// sprite shows its own static sprite, never the base species' GIF.
@MainActor
final class MegaSpriteSurfaceTests: XCTestCase {
    private let lucarioZ = MegaSurfaceFixture.lucarioZ
    private let charizardX = MegaSurfaceFixture.charizardX

    // MARK: Where the Mega form is drawn

    func testTheHolderIsDrawnAsMegaOnlyWhereItAppears() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mega-where-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = try await MegaSurfaceFixture.makeStore(activeIsLucario: false, scratch: scratch)
        XCTAssertTrue(store.equip(lucarioZ, to: "lucario"))

        // A graduated holder that is neither raised, a friend nor the representative changes nothing at home.
        XCTAssertNil(store.currentMegaSpriteID)
        XCTAssertNil(store.representativeSubject.megaSpriteID)
        XCTAssertTrue(store.friendSubjects.isEmpty)

        XCTAssertTrue(store.addFriend(entryID: "lucario"))
        XCTAssertEqual(store.friendSubjects.map(\.megaSpriteID), [lucarioZ.megaID])
        XCTAssertEqual(store.friendSubjects.first?.spriteSpeciesID, lucarioZ.megaID)
        XCTAssertEqual(store.friendSubjects.first?.speciesID, 448)
        XCTAssertNil(store.friendSubjects.first?.spriteForm)
        XCTAssertEqual(store.friendSubjects.first?.spriteIsFemale, false)

        store.unequip(from: "lucario")
        XCTAssertEqual(store.friendSubjects.map(\.megaSpriteID), [nil])
        XCTAssertEqual(store.friendSubjects.first?.spriteSpeciesID, 448)
        XCTAssertEqual(store.friendSubjects.first?.spriteForm, store.friendSubjects.first?.form)
        XCTAssertEqual(store.friendSubjects.first?.spriteIsFemale, store.friendSubjects.first?.isFemale)

        XCTAssertTrue(store.equip(lucarioZ, to: "lucario"))
        XCTAssertEqual(store.friendSubjects.map(\.megaSpriteID), [lucarioZ.megaID],
                       "equipping after the friend joined must reach the friend slot too")
        XCTAssertTrue(store.setRepresentativeSpeciesID(448))
        XCTAssertEqual(store.representativeSubject.spriteSpeciesID, lucarioZ.megaID)
    }

    func testTheStoneHintNamesWhereTheMegaFormShows() {
        XCTAssertTrue(L(.en).megaStoneEffect.contains("raised, friend or representative"))
        XCTAssertTrue(L(.ko).megaStoneEffect.contains("키우는 포켓몬·친구 포켓몬·대표 포켓몬"))
        let english = L(.en).megaStoneEffect
        for language in AppLanguage.allCases where language != .en {
            let text = L(language).megaStoneEffect
            XCTAssertNotEqual(text, english, "\(language) must be translated")
            XCTAssertGreaterThan(text.count, 60, "\(language) keeps both sentences")
        }
    }

    // MARK: Sprite files — a Mega never falls back to its base species

    func testEveryMegaSpriteIsItsOwnFileAndOnlyTheGifBackedOnesAnimate() {
        var animated = 0
        for stone in MegaStone.all {
            guard let id = stone.spriteID else { continue }
            let still = SpriteStore.spriteURL(speciesID: id, animated: false, shiny: false)
            XCTAssertEqual(still.lastPathComponent, "\(id).png", stone.slug)
            XCTAssertEqual(SpriteStore.cacheKey(speciesID: id, animated: false, shiny: false), "\(id)-s")
            guard PokemonAssets.hasAnimatedSprite(speciesID: id) else { continue }
            animated += 1
            let moving = SpriteStore.spriteURL(speciesID: id, animated: true, shiny: false)
            XCTAssertTrue(moving.path.hasSuffix("/other/showdown/\(id).gif"), stone.slug)
        }
        XCTAssertEqual(animated, 56)
        XCTAssertEqual(MegaStone.animatedSpriteIDs.count, 56)
        XCTAssertTrue(MegaStone.animatedSpriteIDs.isSubset(of: Set(MegaStone.all.map(\.megaID))))
        XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: charizardX.megaID))
        XCTAssertFalse(PokemonAssets.hasAnimatedSprite(speciesID: lucarioZ.megaID))
        XCTAssertFalse(PokemonAssets.hasAnimatedSprite(speciesID: 10301))
    }

    func testAMegaWithoutAGifShowsItsStaticSpriteInEveryAnimatedSurface() async throws {
        let fixture = try SpriteFixture.make()
        defer { fixture.tearDown() }
        let store = SpriteStore(directory: fixture.directory)
        var fallbackCount = 0
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: lucarioZ.megaID, shiny: false, store: store,
            waitBeforeRetry: { _ in throw CancellationError() },   // a regression must fail, not retry forever
            onUnavailable: { fallbackCount += 1 })
        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(fallbackCount, 1, "no GIF exists, so the caller's static fallback is the final state")

        for (shiny, back) in [(false, false), (true, false), (false, true), (true, true)] {
            let image = await SpriteLoader.image(speciesID: lucarioZ.megaID, animated: true, shiny: shiny,
                                                 store: store, back: back)
            XCTAssertNotNil(image, "shiny \(shiny) back \(back)")
        }
        let paths = SpriteStubURLProtocol.state.requests.map(\.path)
        XCTAssertFalse(paths.contains { $0.hasSuffix(".gif") }, "\(paths)")
        XCTAssertFalse(paths.contains { $0.hasSuffix("/448.png") || $0.hasSuffix("/448.gif") },
                       "the base Lucario must never be requested for a Mega form: \(paths)")
        XCTAssertEqual(Set(paths.map { ($0 as NSString).lastPathComponent }), ["10310.png"])
    }

    func testAMegaWithAGifAnimatesFromTheShowdownSet() async throws {
        let fixture = try SpriteFixture.make()
        defer { fixture.tearDown() }
        let store = SpriteStore(directory: fixture.directory)
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: charizardX.megaID, shiny: false, store: store, onUnavailable: {})
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(SpriteStubURLProtocol.state.requests.map(\.path).filter { $0.hasSuffix(".gif") }.count, 1)
        XCTAssertTrue(SpriteStubURLProtocol.state.requests.contains {
            $0.path.hasSuffix("/other/showdown/10034.gif")
        })
    }
}
