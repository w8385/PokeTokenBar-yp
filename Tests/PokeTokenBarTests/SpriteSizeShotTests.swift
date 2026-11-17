import AppKit
import ImageIO
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SizeShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4,
                tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common, names: [4: ["ko": "파이리"], 5: ["ko": "리자드"], 6: ["ko": "리자몽"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Opt-in measurement and screenshots of how sprites from different sources sit in their boxes.
/// Downloads the samples into `<dir>/samples` (never the app's own sprite cache) and writes
/// `measure-<tag>.tsv`, `sprite-size-grid-<tag>.png`, `sprite-size-home-<tag>.png`, `sprite-size-battle-<tag>.png`.
///
///     PTB_SPRITE_SIZE_DIR=/tmp/x PTB_SPRITE_SIZE_TAG=before swift test --filter SpriteSizeShotTests
@MainActor
final class SpriteSizeShotTests: XCTestCase {
    enum Kind: String, CaseIterable {
        case png, gif, shinyPNG, backPNG
        var animated: Bool { self == .gif }
        var shiny: Bool { self == .shinyPNG }
        var back: Bool { self == .backPNG }
    }

    static let species: [(String, Int)] = [
        ("Caterpie", 10), ("Bulbasaur", 1), ("Charizard", 6), ("Pikachu", 25), ("Gengar", 94),
        ("Magikarp", 129), ("Snorlax", 143), ("Dragonite", 149), ("Lugia", 249), ("Treecko", 252),
        ("Wailord", 321), ("Rayquaza", 384), ("Lucario", 448), ("Giratina", 487), ("Snivy", 495),
        ("Kyurem", 646), ("Greninja", 658), ("Zygarde", 718), ("Mimikyu", 778), ("Corviknight", 823),
        ("Eternatus", 890), ("Sprigatito", 906), ("Skeledirge", 911), ("Tinkaton", 959),
        ("Iron Valiant", 1006), ("Koraidon", 1007), ("Miraidon", 1008), ("Ogerpon", 1017),
        ("Terapagos", 1024), ("Pecharunt", 1025)]
    static let megas: [(String, Int)] = [
        ("Mega Venusaur", 10033), ("Mega Charizard X", 10034), ("Mega Blastoise", 10036),
        ("Mega Gengar", 10038), ("Mega Mewtwo X", 10043), ("Mega Rayquaza", 10079),
        ("Mega Garchomp", 10058), ("Mega Gyarados", 10041), ("Mega Absol", 10057), ("Mega Z-A static", 10287)]
    static let boxSizes: [(String, CGFloat)] = [("battle56", 56), ("home76", 76), ("pet96", 96), ("box104", 104)]

    private var all: [(String, Int)] { Self.species + Self.megas }

    private struct Cell: View {
        let id: Int
        let kind: Kind
        let size: CGFloat
        let store: SpriteStore
        var body: some View {
            SpriteView(speciesID: id, size: size, animated: kind.animated, shiny: kind.shiny,
                       spriteStore: store, back: kind.back)
                .frame(width: size, height: size)
        }
    }

    func testMeasureAndShoot() async throws {
        guard let out = ProcessInfo.processInfo.environment["PTB_SPRITE_SIZE_DIR"] else {
            throw XCTSkip("Set PTB_SPRITE_SIZE_DIR to write the sprite size measurements and screenshots")
        }
        let tag = ProcessInfo.processInfo.environment["PTB_SPRITE_SIZE_TAG"] ?? "after"
        let directory = URL(fileURLWithPath: out)
        let samples = directory.appendingPathComponent("samples")
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        let store = SpriteStore(directory: samples)

        for (_, id) in all {
            for kind in Kind.allCases {
                _ = await store.data(speciesID: id, animated: kind.animated, shiny: kind.shiny, back: kind.back)
            }
        }

        var rows: [String] = ["id\tlabel\tkind\tcanvasW\tcanvasH\tframes\tbboxW\tbboxH"
            + Self.boxSizes.map { "\t\($0.0)H\t\($0.0)Gap" }.joined()]
        var rendered: [String: [Kind: [String: (h: Int, gap: Int)]]] = [:]
        for (name, size) in Self.boxSizes {
            let measured = try await renderMeasure(store: store, size: size)
            for (key, value) in measured { rendered[key, default: [:]][value.0, default: [:]][name] = value.1 }
        }
        XCTAssertNotNil(rendered["10034"], "Mega Charizard X was not rendered")
        for (label, id) in all {
            for kind in Kind.allCases {
                let file = samples.appendingPathComponent(
                    "\(SpriteStore.cacheKey(speciesID: id, animated: kind.animated, shiny: kind.shiny, back: kind.back)).\(kind.animated ? "gif" : "png")")
                guard let raw = Self.rawMetrics(file) else {
                    rows.append("\(id)\t\(label)\t\(kind.rawValue)\t-\t-\t-\t-\t-"); continue
                }
                var line = "\(id)\t\(label)\t\(kind.rawValue)\t\(raw.canvas.0)\t\(raw.canvas.1)\t\(raw.frames)\t\(raw.bbox.0)\t\(raw.bbox.1)"
                for (name, _) in Self.boxSizes {
                    let r = rendered["\(id)"]?[kind]?[name]
                    line += "\t\(r.map { String($0.h) } ?? "-")\t\(r.map { String($0.gap) } ?? "-")"
                }
                rows.append(line)
            }
        }
        try rows.joined(separator: "\n").write(to: directory.appendingPathComponent("measure-\(tag).tsv"),
                                               atomically: true, encoding: .utf8)

        try writeLoadCost(samples: samples, to: directory.appendingPathComponent("load-cost-\(tag).txt"))
        try await shootGrid(store: store, to: directory.appendingPathComponent("sprite-size-grid-\(tag).png"))
        try await shootHomeAndBattle(directory: directory, tag: tag)
    }

    /// One-time decode cost of every sampled GIF: plain ImageIO decode vs `SpriteFrame.decode` (decode + union
    /// scan + crop), and the pixel bytes the decoded frames hold before and after the crop.
    private func writeLoadCost(samples: URL, to file: URL) throws {
        let gifs = try FileManager.default.contentsOfDirectory(at: samples, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "gif" }
        var rawMs = 0.0, cropMs = 0.0, worstMs = 0.0, rawBytes = 0, cropBytes = 0
        for url in gifs {
            let data = try Data(contentsOf: url)
            var start = Date()
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let raw = (0..<CGImageSourceGetCount(source)).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
            rawMs += Date().timeIntervalSince(start) * 1000
            start = Date()
            let decoded = try XCTUnwrap(SpriteFrame.decode(data))
            let ms = Date().timeIntervalSince(start) * 1000
            cropMs += ms; worstMs = max(worstMs, ms)
            rawBytes += raw.reduce(0) { $0 + $1.width * $1.height * 4 }
            cropBytes += decoded.reduce(0) { $0 + Int($1.image.size.width * $1.image.size.height) * 4 }
        }
        let text = "gifs=\(gifs.count) rawDecodeMs=\(Int(rawMs)) cropDecodeMs=\(Int(cropMs)) worstOneGifMs=\(Int(worstMs)) "
            + "rawFrameBytes=\(rawBytes) croppedFrameBytes=\(cropBytes)\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Union opaque bounding box over every frame of a PNG/GIF file, scanned independently of production code.
    static func rawMetrics(_ file: URL) -> (canvas: (Int, Int), frames: Int, bbox: (Int, Int))? {
        guard let data = try? Data(contentsOf: file), let src = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(src) > 0 else { return nil }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        var canvas = (0, 0)
        for index in 0..<CGImageSourceGetCount(src) {
            guard let cg = CGImageSourceCreateImageAtIndex(src, index, nil) else { continue }
            canvas = (cg.width, cg.height)
            guard let box = opaqueBox(of: cg) else { continue }
            minX = min(minX, box.minX); minY = min(minY, box.minY)
            maxX = max(maxX, box.maxX); maxY = max(maxY, box.maxY)
        }
        guard maxX >= 0 else { return (canvas, CGImageSourceGetCount(src), (0, 0)) }
        return (canvas, CGImageSourceGetCount(src), (maxX - minX + 1, maxY - minY + 1))
    }

    static func opaqueBox(of cg: CGImage, threshold: UInt8 = 16) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where p[(y * w + x) * 4 + 3] > threshold {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return maxX >= 0 ? (minX, minY, maxX, maxY) : nil
    }

    /// Renders every sample in every kind at one box size, one host per cell (cells seed from the
    /// cache synchronously, so frame 0 of an animation is what is measured), and measures the opaque rows.
    private func renderMeasure(store: SpriteStore, size: CGFloat) async throws -> [(String, (Kind, (h: Int, gap: Int)))] {
        var out: [(String, (Kind, (h: Int, gap: Int)))] = []
        for item in all {
            for kind in Kind.allCases {
                let host = OffscreenRender.host(Cell(id: item.1, kind: kind, size: size, store: store),
                                                size: CGSize(width: size, height: size), appearance: .aqua)
                let bitmap = try OffscreenRender.bitmap(of: host)
                var top = Int.max, bottom = -1
                for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide
                    where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.07 {
                    top = min(top, y); bottom = max(bottom, y)
                } }
                let scale = CGFloat(bitmap.pixelsHigh) / size
                if bottom >= 0 {
                    out.append(("\(item.1)", (kind, (Int((CGFloat(bottom - top + 1) / scale).rounded()),
                                                    Int((CGFloat(bitmap.pixelsHigh - 1 - bottom) / scale).rounded())))))
                }
            }
        }
        return out
    }

    private func shootGrid(store: SpriteStore, to file: URL) async throws {
        let size: CGFloat = 64, gap: CGFloat = 6
        let rows: [(String, Int)] = [("Caterpie", 10), ("Pikachu", 25), ("Charizard", 6), ("Snorlax", 143),
                                     ("Wailord", 321), ("Rayquaza", 384), ("Greninja", 658), ("Mimikyu", 778),
                                     ("Koraidon", 1007), ("Mega Charizard X", 10034), ("Mega Venusaur", 10033),
                                     ("Mega Rayquaza", 10079), ("Mega Z-A static", 10287)]
        let kinds = Kind.allCases
        func cell(_ id: Int, _ kind: Kind) -> some View {
            Cell(id: id, kind: kind, size: size, store: store)
                .background(Color.gray.opacity(0.12))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.red.opacity(0.55)).frame(height: 1) }
                .overlay(Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5))
        }
        let grid = VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: gap) {
                Text("").frame(width: 112)
                ForEach(kinds, id: \.rawValue) { Text($0.rawValue).font(.system(size: 10)).frame(width: size) }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) {
                    Text("\(row.0)\n#\(row.1)").font(.system(size: 10)).frame(width: 112, alignment: .leading)
                    ForEach(kinds, id: \.rawValue) { cell(row.1, $0) }
                }
            }
        }.padding(10)
        let width = 112 + (size + gap) * CGFloat(kinds.count) + 20
        let height = (size + gap) * CGFloat(rows.count + 1) + 20
        try await OffscreenRender.capture(grid.frame(width: width, height: height, alignment: .topLeading)
            .background(Color.white).environment(\.colorScheme, .light),
            size: CGSize(width: width, height: height), appearance: .aqua, scale: 2, settle: .seconds(2), to: file)
    }

    private func shootHomeAndBattle(directory: URL, tag: String) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("size-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 2, usedAtStage: 0,
                                rarity: .common, totalForms: 3,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        var ids: [String] = []
        for (n, (finalID, chain)) in [(6, [4, 5, 6]), (25, [25]), (321, [321])].enumerated() {
            var profile = PokemonProfile.generate(seed: UInt64(6 + n), instanceID: "e\(n)")
            profile.level = 50
            var entry = DexEntry(baseID: chain[0], finalID: finalID, chainOrder: chain, rarity: .common,
                                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                                 names: [finalID: ["ko": "샘플\(finalID)", "en": "Sample"]])
            entry.id = "e\(n)"
            ids.append(entry.id)
            state.dex.append(entry)
        }
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: SizeShotProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: 6)
        let nav = PopoverNavigation()
        let defaults = UserDefaults(suiteName: "size-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        for id in ids { _ = battle.add(id) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data("{\"moves\":[],\"default\":[]}".utf8), 200) },
            partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        func capture<V: View>(_ view: V, height: CGFloat, name: String) async throws {
            let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
            try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
                .background(Color.white).environment(\.colorScheme, .light)
                .environment(\.locale, AppLanguage.ko.displayLocale),
                size: size, appearance: .aqua, scale: 2, settle: .seconds(5),
                to: directory.appendingPathComponent("sprite-size-\(name)-\(tag).png"))
        }
        try await capture(CompanionHeader(store: store), height: 300, name: "home")
        try await capture(BattleView(store: store, navigation: nav, initialPickerQuery: "")
            .environment(uploader).environment(battle).environment(store), height: 620, name: "battle")
    }
}
