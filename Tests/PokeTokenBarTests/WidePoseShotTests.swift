import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in: renders the production `SpriteView` for Vanillite and the wide poses `SpriteFit.animatedSize` scales up,
/// and writes how far each body reaches past its slot. Downloads the sprites into `<dir>/samples`.
///
///     PTB_WIDE_POSE_DIR=/tmp/x PTB_WIDE_POSE_TAG=after swift test --filter WidePoseShotTests
@MainActor
final class WidePoseShotTests: XCTestCase {
    static let sprites: [(String, Int)] = [
        ("Vanillite", 582), ("Lugia", 249), ("Greninja", 658), ("Corviknight", 823), ("Tinkaton", 959),
        ("Koraidon", 1007), ("Mega Venusaur", 10033), ("Mega Charizard X", 10034), ("Mega Garchomp", 10058),
        ("Mega Gyarados", 10041)]
    static let boxes: [CGFloat] = [76, 96]

    func testRenderWidePoses() async throws {
        guard let out = ProcessInfo.processInfo.environment["PTB_WIDE_POSE_DIR"] else {
            throw XCTSkip("Set PTB_WIDE_POSE_DIR to write the wide pose renders")
        }
        let tag = ProcessInfo.processInfo.environment["PTB_WIDE_POSE_TAG"] ?? "after"
        let directory = URL(fileURLWithPath: out)
        let samples = directory.appendingPathComponent("samples")
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        let store = SpriteStore(directory: samples)
        for (_, id) in Self.sprites {
            _ = await store.data(speciesID: id, animated: true)
            _ = await store.data(speciesID: id, animated: false)
        }

        var rows = ["name\tid\tbodyLeft\tbodyRight\tbox\tscale\tshiftPt\tbodyOverflowPt"]
        for (name, id) in Self.sprites {
            let frames = SpriteLoader.cachedFrames(speciesID: id, shiny: false, directory: samples).map(\.image)
            let still = SpriteLoader.cachedImage(speciesID: id, directory: samples)
            guard let first = frames.first, let still else { rows.append("\(name)\t\(id)\tno sprite"); continue }
            let span = SpriteBody.span(first: first) { frames }
            for box in Self.boxes {
                let content = SpriteFit.contentBox(box)
                let fit = SpriteFit.animatedSize(for: first.size, reference: still.size, box: content, body: span)
                let plain = SpriteFit.size(for: first.size, box: content)
                let dx = SpriteFit.bodyOffset(drawn: fit, body: span)
                let reach = span.map { max(abs(dx + ($0.lowerBound - 0.5) * fit.width),
                                           abs(dx + ($0.upperBound - 0.5) * fit.width)) } ?? 0
                rows.append("\(name)\t\(id)\t\(span.map { String(format: "%.2f", $0.lowerBound) } ?? "-")"
                    + "\t\(span.map { String(format: "%.2f", $0.upperBound) } ?? "-")\t\(Int(box))"
                    + "\t\(String(format: "%.2f", fit.width / plain.width))\t\(String(format: "%.1f", dx))"
                    + "\t\(String(format: "%.1f", max(0, reach - content / 2)))")
            }
        }
        try rows.joined(separator: "\n").write(to: directory.appendingPathComponent("wide-pose-\(tag).tsv"),
                                               atomically: true, encoding: .utf8)

        let cell: CGFloat = 96, gap: CGFloat = 8
        func tile(_ id: Int, animated: Bool, size: CGFloat) -> some View {
            SpriteView(speciesID: id, size: size, animated: animated, spriteStore: store)
                .frame(width: size, height: size)
                .background(Color.gray.opacity(0.12))
                .overlay(Rectangle().stroke(Color.red.opacity(0.6), lineWidth: 0.5))
                .frame(width: cell, height: cell, alignment: .bottomLeading)
        }
        let grid = VStack(alignment: .leading, spacing: gap) {
            ForEach(Self.sprites, id: \.1) { _, id in
                HStack(spacing: gap) {
                    tile(id, animated: false, size: 76)
                    tile(id, animated: true, size: 76)
                    tile(id, animated: true, size: 96)
                }
            }
        }.padding(10)
        let legend = Text("columns: static 76pt | animated 76pt (Home box) | animated 96pt (floating pet default)")
            .font(.system(size: 9))
        let width = (cell + gap) * 3 + 20, height = (cell + gap) * CGFloat(Self.sprites.count) + 20
        try await OffscreenRender.capture(VStack(alignment: .leading, spacing: 0) { legend.padding(.horizontal, 10); grid }
            .frame(width: width, height: height + 16, alignment: .topLeading)
            .background(Color.white).environment(\.colorScheme, .light),
            size: CGSize(width: width, height: height + 16), appearance: .aqua, scale: 2, settle: .seconds(1),
            to: directory.appendingPathComponent("wide-pose-grid-\(tag).png"))
    }
}
