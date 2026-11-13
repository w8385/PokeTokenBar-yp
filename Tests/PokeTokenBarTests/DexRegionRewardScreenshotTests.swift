import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in captures for the PR: synthetic data, real views.
///
///     PTB_REGION_REWARD_SHOT_DIR=/tmp/shots swift test --filter DexRegionRewardScreenshotTests
@MainActor
final class DexRegionRewardScreenshotTests: XCTestCase {
    func testCaptureCelebrationAndChipMark() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_REGION_REWARD_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_REGION_REWARD_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let l = L(.en)
        let items = "\(l.itemName(.rareCandy)) ×\(DexRegionReward.candyCount), \(l.itemName(.shinyCharm))"
        let text = FloatingPetView.hoverTooltip(todayTokens: 12_345_678, limitUtilization: nil, mode: .used, l: l,
                                                eventLine: l.notifDexRegionRewardBody(l.regionName(.kanto), items: items))
        for (scheme, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let view = FloatingPetController.hoverCalloutView(text: text, appearance: NSAppearance(named: scheme)!)
            try write(view, appearance: NSAppearance(named: scheme)!, to: directory.appendingPathComponent("region-reward-celebration-\(name).png"))
        }

        let rewarded = DexCompletion(region: .kanto, owned: 151, shinyOwned: 0)
        let done = DexCompletion(region: .johto, owned: 100, shinyOwned: 0)
        let partial = DexCompletion(region: .hoenn, owned: 40, shinyOwned: 0)
        let chips = HStack(spacing: 4) {
            RegionTally(label: l.regionName(.kanto), completion: rewarded, isRewarded: true)
            RegionTally(label: l.regionName(.johto), completion: done)
            RegionTally(label: l.regionName(.hoenn), completion: partial)
        }
        .fixedSize()
        .padding(12)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: chips)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        try write(host, appearance: NSAppearance(named: .aqua)!,
                  to: directory.appendingPathComponent("region-reward-chip-mark.png"))
    }

    private func write(_ view: NSView, appearance: NSAppearance, to file: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: view.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.backgroundColor = appearance.name == .darkAqua ? NSColor(white: 0.12, alpha: 1) : .white
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: file)
    }
}
