import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct TokenSheet: View {
    private let sizes: [(String, FontSize)] = [
        ("micro", .micro), ("tiny", .tiny), ("caption", .caption), ("small", .small), ("body", .body),
        ("label", .label), ("control", .control), ("lead", .lead), ("headline", .headline),
        ("title", .title), ("display", .display), ("hero", .hero),
    ]
    private let radii: [(String, CGFloat)] = [
        ("hairline", Radius.hairline), ("bar", Radius.bar), ("chip", Radius.chip), ("card", Radius.card),
        ("panel", Radius.panel), ("sheet", Radius.sheet),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Type scale") {
                ForEach(sizes, id: \.0) { name, size in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(name) \(Int(size.points))").font(.ptb(.caption, design: .monospaced))
                            .foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                        Text("Pokémon 포켓몬 1,234").font(.ptb(size)).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
            }
            section("Radius") {
                HStack(spacing: 10) {
                    ForEach(radii, id: \.0) { name, radius in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: radius).fill(Color.accentColor.opacity(0.25))
                                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.accentColor, lineWidth: 1))
                                .frame(width: 40, height: 40)
                            Text(name).font(.ptb(.tiny)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            section("Shadow") {
                HStack(spacing: 18) {
                    ForEach([("lift", ShadowStyle.lift), ("bubble", .bubble), ("glyph", .glyph)], id: \.0) { name, style in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: Radius.card).fill(Color(nsColor: .windowBackgroundColor))
                                .ptbShadow(style).frame(width: 52, height: 34)
                            Text(name).font(.ptb(.tiny)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            section("Palette") {
                swatches(Palette.providerSeries)
                swatches([Palette.sun, Palette.moon, Palette.heart])
                swatches([Palette.Recap.shellTop, Palette.Recap.shellBottom, Palette.Recap.screenInk, Palette.Recap.lcd,
                          Palette.Recap.amber, Palette.Recap.ledRed, Palette.Recap.ledYellow, Palette.Recap.ledGreen,
                          Palette.Recap.lensHighlight, Palette.Recap.lensBody])
            }
            section("Components") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ptbCard").font(.ptb(.label)).padding(10).frame(maxWidth: .infinity, alignment: .leading).ptbCard()
                    Text("ptbPanel").font(.ptb(.label)).padding(10).frame(maxWidth: .infinity, alignment: .leading).ptbPanel()
                    HStack(spacing: 8) {
                        chip("circle.dashed", nil)
                        chip("circle.dashed.inset.filled", .accent)
                        chip("sparkle", nil)
                        chip("sparkles", .shiny)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.ptb(.caption, weight: .bold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func swatches(_ colors: [Color]) -> some View {
        HStack(spacing: 3) {
            ForEach(colors.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: Radius.bar).fill(colors[index]).frame(width: 15, height: 15)
            }
        }
    }

    private func chip(_ symbol: String, _ tint: ChipTint?) -> some View {
        Image(systemName: symbol).font(.ptb(.control, weight: tint == nil ? .regular : .bold))
            .foregroundStyle(tint?.color ?? .secondary)
            .frame(width: 16, height: 16).padding(.horizontal, 6).padding(.vertical, 4)
            .ptbChip(active: tint)
    }
}

/// `PTB_DESIGN_SHEET_DIR=<dir>` writes the token sheet that docs and PRs show.
@MainActor
final class DesignTokenSheetTests: XCTestCase {
    func testTokenSheetRenders() async throws {
        let host = OffscreenRender.host(TokenSheet().environment(\.colorScheme, .light), size: CGSize(width: 360, height: 700),
                                        appearance: .aqua)
        host.frame.size = host.fittingSize
        try await OffscreenRender.settle(host)
        let data = try OffscreenRender.png(of: host, scale: 2)
        XCTAssertGreaterThan(host.bounds.height, 400)
        if let dir = ProcessInfo.processInfo.environment["PTB_DESIGN_SHEET_DIR"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("token-sheet.png"))
        }
    }
}
