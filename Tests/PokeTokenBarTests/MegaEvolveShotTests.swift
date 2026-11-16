import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in offscreen render of the effect as a frame strip. Needs `PTB_MEGA_FX_DIR` (output) and
/// `PTB_SPRITE_SIZE_DIR` (a folder whose `samples/` holds `6-s.png` and `10034-s.png`).
@MainActor
final class MegaEvolveShotTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let times: [TimeInterval] = [0, 0.3, 0.5, 0.62, 0.85, 1.4]

    private func store() throws -> SpriteStore {
        guard let base = ProcessInfo.processInfo.environment["PTB_SPRITE_SIZE_DIR"] else {
            throw XCTSkip("Set PTB_SPRITE_SIZE_DIR to a folder whose samples/ holds the sprite PNGs")
        }
        return SpriteStore(directory: URL(fileURLWithPath: base).appendingPathComponent("samples"))
    }

    private func renderAt(_ t: TimeInterval, reduceMotion: Bool) -> MegaEvolveRender {
        var model = MegaEvolveStageModel()
        let event = MegaEvolveEvent(id: 1, kind: .equip, instanceID: "x", megaSpriteID: 10034, at: start)
        model.megaChanged(from: nil, to: 10034, event: event, now: start, reduceMotion: reduceMotion)
        return model.render(at: start.addingTimeInterval(t), megaSpriteID: 10034)
    }

    private func strip(dark: Bool, reduceMotion: Bool, store: SpriteStore) -> some View {
        let times = reduceMotion ? [0, 0.06, 0.125, 0.19, 0.25, 0.3] : Self.times
        return HStack(spacing: 6) {
            ForEach(times, id: \.self) { t in
                let render = self.renderAt(t, reduceMotion: reduceMotion)
                VStack(spacing: 4) {
                    MegaEvolveRenderView(render: render, size: 104) { mega in
                        SpriteView(speciesID: mega ?? 6, size: 104, spriteStore: store)
                    }
                    .frame(width: 104, height: 104)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Text(String(format: "%.2fs", t)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(dark ? Color(white: 0.1) : Color(white: 0.97))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    func testRenderTheFrameStrips() async throws {
        guard let dir = ProcessInfo.processInfo.environment["PTB_MEGA_FX_DIR"] else {
            throw XCTSkip("Set PTB_MEGA_FX_DIR (and PTB_SPRITE_SIZE_DIR) to write the frame strips")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = try store()
        let size = CGSize(width: 6 * 104 + 5 * 6 + 20, height: 104 + 4 + 14 + 20)
        for (name, dark, reduce) in [("mega-fx-strip-light", false, false), ("mega-fx-strip-dark", true, false),
                                     ("mega-fx-strip-reduce-motion", false, true)] {
            let renderer = ImageRenderer(content: strip(dark: dark, reduceMotion: reduce, store: store)
                .frame(width: size.width, height: size.height))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testRenderTheSlackMessageIllustration() throws {
        guard let dir = ProcessInfo.processInfo.environment["PTB_MEGA_FX_DIR"],
              let base = ProcessInfo.processInfo.environment["PTB_SPRITE_SIZE_DIR"] else {
            throw XCTSkip("Set PTB_MEGA_FX_DIR and PTB_SPRITE_SIZE_DIR to write the Slack message illustration")
        }
        let mega = try XCTUnwrap(NSImage(contentsOf: URL(fileURLWithPath: base).appendingPathComponent("samples/10034-s.png")))
        func grey(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(Color(white: 0.4)) }
        let message = VStack(alignment: .leading, spacing: 8) {
            Text("Illustration of the battle message (sample data)").font(.caption2).foregroundStyle(.secondary)
            Text("🏆 @alice 승").font(.system(size: 15, weight: .bold))
            Text("1:1 · 6턴").font(.system(size: 13))
            HStack(alignment: .top, spacing: 40) {
                Text("🔵 @alice\n리자몽(메가) ▰▰▰▰▰▱▱▱▱▱ 54%").font(.system(size: 13))
                Text("🔴 @bob\n거북왕 💥").font(.system(size: 13))
            }
            Text("다시 붙기").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.7)))
            HStack(spacing: 6) {
                Image(nsImage: mega).resizable().scaledToFit().frame(width: 20, height: 20)
                Text("리자몽 메가진화").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.3))
            }
            Divider()
            grey("1턴").bold()
            grey("🔵 리자몽 메가진화 [단단한발톱]")
            grey("🔵 리자몽 › 몸통박치기 → 거북왕 84%")
        }
        .padding(16).frame(width: 420, alignment: .leading).background(Color.white).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: message)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("mega-fx-bot-message.png"))
    }

    func testTheGlowAndFlashActuallyDrawWhiteOverTheSprite() throws {
        func whiteShare(_ t: TimeInterval) throws -> Double {
            let view = MegaEvolveRenderView(render: renderAt(t, reduceMotion: false), size: 60) { _ in
                Rectangle().fill(Color(red: 0.2, green: 0.3, blue: 0.8)).frame(width: 40, height: 40)
            }
            .frame(width: 60, height: 60).background(Color.black)
            let image = try XCTUnwrap(ImageRenderer(content: view).cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
                .usingColorSpace(.deviceRGB))
            return Double(center.redComponent + center.greenComponent + center.blueComponent) / 3
        }
        let rest = try whiteShare(0)
        XCTAssertGreaterThan(try whiteShare(0.4), rest + 0.3, "the base sprite charges up white before any flash")
        XCTAssertGreaterThan(try whiteShare(MegaEvolveFX.swapTime), 0.85, "the flash covers the swap")
        XCTAssertEqual(try whiteShare(MegaEvolveFX.duration + 0.1), rest, accuracy: 0.001, "nothing is left drawn")
    }
}
