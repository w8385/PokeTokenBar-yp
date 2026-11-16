import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class SessionKeySettingsRenderingTests: XCTestCase {
    func testSessionKeyEntryOpensTheAdvancedTabInsideTheViewport() async throws {
        let suite = "SessionKeySettingsRendering-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let companion = CompanionStore(fileURL: file, defaults: defaults)
        companion.setLanguage(.en)
        let navigation = PopoverNavigation(defaults: defaults)
        navigation.openSessionKeySettings()
        let host = renderedSettings(usage, companion, navigation, startExpanded: navigation.expandAdvancedOnOpen)
        let window = OffscreenRender.windowHosting(host.view, appearance: .aqua)
        defer { window.close() }
        try await OffscreenRender.settle(host.view, for: .milliseconds(500))
        let secure = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? NSSecureTextField }.first)
        let rect = secure.convert(secure.bounds, to: host.view)
        XCTAssertTrue(host.view.bounds.contains(rect), "session key entry must be visible after scrolling")
        XCTAssertEqual(navigation.settingsTab, .advanced)
        XCTAssertTrue(navigation.showSettings)
        navigation.reset()
        XCTAssertFalse(navigation.expandAdvancedOnOpen)
    }

    func testDifficultyAndWarningSlidersSurviveOnTheirTabs() async throws {
        let suite = "SettingsTabSliders-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let companion = CompanionStore(fileURL: file, defaults: defaults)
        companion.setLanguage(.en)
        for tab in [SettingsTab.companion, .notifications] {
            let navigation = PopoverNavigation(defaults: defaults)
            navigation.settingsTab = tab
            let host = renderedSettings(usage, companion, navigation, startExpanded: false)
            let window = OffscreenRender.windowHosting(host.view, appearance: .aqua)
            defer { window.close() }
            try await OffscreenRender.settle(host.view, for: .milliseconds(500))
            let views = descendants(of: host.view)
            let nativeSliders = views.compactMap { $0 as? NSSlider }
            if nativeSliders.isEmpty {
                let scroll = try XCTUnwrap(views.compactMap { $0 as? NSScrollView }.first)
                let tracks = try await sliderTrackPositions(host: host.view, scroll: scroll)
                XCTAssertGreaterThanOrEqual(tracks.count, 2, "\(tab) must keep its two slider tracks: \(tracks)")
            } else {
                XCTAssertEqual(nativeSliders.count, 2, "\(tab) must keep its two sliders")
            }
        }
    }

    private func renderedSettings(_ usage: UsageStore, _ companion: CompanionStore,
                                  _ navigation: PopoverNavigation, startExpanded: Bool) -> NSHostingController<some View> {
        let host = NSHostingController(rootView: SettingsView(
            onClose: {}, onChooseRepresentative: {}, startExpanded: startExpanded,
            tab: Binding(get: { navigation.settingsTab }, set: { navigation.settingsTab = $0 }))
            .environment(usage).environment(companion).environment(UpdateChecker())
            .frame(width: PopoverMetrics.width)
            .environment(\.colorScheme, .light))
        host.view.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.width, height: 460)
        return host
    }

    /// Distinct vertical positions, in document points, of a slider-track stroke: a horizontal run of
    /// ink 60pt or longer that starts and ends inside the middle of the row. A divider spans the whole
    /// width and a label is short, so neither counts. Scrolls the whole document, one viewport at a time.
    private func sliderTrackPositions(host: NSView, scroll: NSScrollView) async throws -> [CGFloat] {
        let document = try XCTUnwrap(scroll.documentView)
        let clip = scroll.contentView
        let maximum = max(0, document.bounds.height - clip.bounds.height)
        let step = max(1, clip.bounds.height - 40)
        var positions: [CGFloat] = []
        for offset in stride(from: 0.0, through: maximum + step, by: step) {
            let origin = min(offset, maximum)
            clip.scroll(to: NSPoint(x: 0, y: origin))
            scroll.reflectScrolledClipView(clip)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = Double(bitmap.pixelsWide) / host.bounds.width
            for y in 0..<bitmap.pixelsHigh {
                var run = 0, start = 0
                for x in 0...bitmap.pixelsWide {
                    var isInk = false
                    if x < bitmap.pixelsWide,
                       let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                        let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                        isInk = color.alphaComponent > 0.9 && brightness > 0.05 && brightness < 0.9
                    }
                    if isInk {
                        if run == 0 { start = x }
                        run += 1
                    } else if run > 0 {
                        let length = Double(run) / scale
                        let from = Double(start) / (scale * host.bounds.width)
                        let to = Double(x) / (scale * host.bounds.width)
                        if length >= 60, from >= 0.3, to <= 0.8 {
                            let position = origin + CGFloat(Double(y) / scale)
                            if !positions.contains(where: { abs($0 - position) < 6 }) { positions.append(position) }
                        }
                        run = 0
                    }
                }
            }
        }
        return positions.sorted()
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
