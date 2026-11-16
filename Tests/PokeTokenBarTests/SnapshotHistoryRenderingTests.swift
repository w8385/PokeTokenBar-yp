import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SnapshotHistoryOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Drives the production Settings disclosure, including rows outside the scroll viewport.
@MainActor
final class SnapshotHistoryRenderingTests: XCTestCase {
    private var window: NSWindow?
    private var renderNumber = 0

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    func testTenSnapshotsStartCollapsedAndExpandAllRowsThenCollapseAndReopen() async throws {
        let (companion, usage) = try makeStores(snapshotCount: 10)
        let root = host(companion, usage)
        let document = try await settingsDocument(in: root)
        try await settle(document, capture: "snapshots-collapsed")
        let collapsedHeight = document.bounds.height

        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await settle(document, capture: "snapshots-expanded")
        XCTAssertGreaterThan(document.bounds.height, collapsedHeight + 200)
        XCTAssertEqual(companion.availableSnapshots.count, 10)

        try await toggleHistory(in: document, l: companion.l, expanded: true)
        try await settle(document, capture: "snapshots-collapsed-again")
        XCTAssertEqual(document.bounds.height, collapsedHeight, accuracy: 2)

        // Reopening Settings starts a new visit, even after leaving its history expanded.
        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await settle(document)
        window?.close()
        let reopened = host(companion, usage)
        let reopenedDocument = try await settingsDocument(in: reopened)
        try await settle(reopenedDocument, capture: "snapshots-reopened")
        XCTAssertEqual(reopenedDocument.bounds.height, collapsedHeight, accuracy: 2, "a new visit starts collapsed")
        XCTAssertEqual(companion.availableSnapshots.count, 10)
    }

    func testEmptyHistoryIsDisclosedAndManualCreationRemainsAvailable() async throws {
        let (companion, usage) = try makeStores(snapshotCount: 0)
        let document = try await settingsDocument(in: host(companion, usage))
        try await settle(document)
        let collapsedHeight = document.bounds.height

        // The empty-state line is the only thing expanding an empty history adds.
        XCTAssertTrue(companion.availableSnapshots.isEmpty)
        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await settle(document, capture: "snapshots-empty-expanded")
        XCTAssertGreaterThan(document.bounds.height, collapsedHeight + 8, "expanding must show the empty-state row")
    }

    private func makeStores(snapshotCount: Int) throws -> (CompanionStore, UsageStore) {
        let suite = "SnapshotHistoryRendering-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let file = directory.appendingPathComponent("companion-state.json")
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1], stageIndex: 0,
                                usedAtStage: 0, rarity: .common, totalForms: 1)
        for index in 0..<snapshotCount {
            state.usedSinceInstall = 10_000 + index * 1_000
            try SaveSnapshotManager.createSnapshot(state: state, for: file,
                date: now.addingTimeInterval(Double(index - snapshotCount) * 3600),
                appVersion: "sample", deviceName: "Sample data")
        }
        state.usedSinceInstall = 99_000
        try JSONEncoder().encode(state).write(to: file)

        // Sample screenshots use a generated geometric icon, never downloaded Pokémon artwork.
        let image = NSImage(size: NSSize(width: 28, height: 28), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 4, yRadius: 4).fill()
            return true
        }
        let key = SpriteLoader.cacheDir.appendingPathComponent("1-s.png").path as NSString
        let previous = SpriteLoader.imageCache.object(forKey: key)
        SpriteLoader.imageCache.setObject(image, forKey: key)
        addTeardownBlock { @MainActor in
            if let previous { SpriteLoader.imageCache.setObject(previous, forKey: key) }
            else { SpriteLoader.imageCache.removeObject(forKey: key) }
        }
        return (CompanionStore(provider: SnapshotHistoryOfflineProvider(), clock: { now },
                               fileURL: file, defaults: defaults),
                UsageStore(providers: [], autoRefresh: false, defaults: defaults))
    }

    private func host(_ companion: CompanionStore, _ usage: UsageStore) -> NSView {
        let host = NSHostingView(rootView: SettingsView(onClose: {}, onChooseRepresentative: {})
            .environment(companion).environment(usage).environment(UpdateChecker())
            .environment(\.colorScheme, .light)
            .frame(width: PopoverMetrics.width))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.width, height: 460)
        window = OffscreenRender.windowHosting(host, appearance: .aqua)
        return host
    }

    private func settingsDocument(in root: NSView) async throws -> NSView {
        try await Task.sleep(for: .milliseconds(300))
        root.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }.first)
        return try XCTUnwrap(scroll.documentView)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func diagnosticDirectory() throws -> URL? {
        guard let path = ProcessInfo.processInfo.environment["PTB_SNAPSHOT_SCREENSHOT_DIR"] else { return nil }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent(name.filter { $0.isLetter || $0.isNumber }, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func bitmap(of view: NSView) async throws -> NSBitmapImageRep {
        view.window?.contentView?.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let scroll = try XCTUnwrap(view.enclosingScrollView)
        let clip = scroll.contentView
        let originalOrigin = clip.bounds.origin
        defer {
            clip.scroll(to: originalOrigin)
            scroll.reflectScrolledClipView(clip)
            view.window?.contentView?.layoutSubtreeIfNeeded()
        }
        let width = Int((bounds.width * 2).rounded(.up))
        let height = Int((bounds.height * 2).rounded(.up))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }

        // Native controls may draw only inside the current viewport. Capture every actual
        // visible tile at 2x, rather than asking offscreen controls to draw the whole document.
        let tileLimit = Int((bounds.height / max(clip.bounds.height, 1)).rounded(.up)) + 2
        var coveredY = bounds.minY
        var tiles = [[String: Any]]()
        for _ in 0..<tileLimit where coveredY < bounds.maxY - 0.5 {
            clip.scroll(to: NSPoint(x: bounds.minX, y: coveredY))
            scroll.reflectScrolledClipView(clip)
            view.window?.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            view.window?.contentView?.layoutSubtreeIfNeeded()
            let rect = view.visibleRect.intersection(bounds)
            guard rect.width >= bounds.width - 0.5, rect.minY <= coveredY + 0.5,
                  rect.maxY > coveredY + 0.5 else {
                XCTFail("Snapshot tile did not cover document: tile=\(rect), coveredY=\(coveredY), bounds=\(bounds)")
                throw URLError(.cannotParseResponse)
            }
            let tile = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int((rect.width * 2).rounded(.up)),
                pixelsHigh: Int((rect.height * 2).rounded(.up)), bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            tile.size = rect.size
            view.cacheDisplay(in: rect, to: tile)
            XCTAssertGreaterThanOrEqual(CGFloat(tile.pixelsWide) / rect.width, 2)
            XCTAssertGreaterThanOrEqual(CGFloat(tile.pixelsHigh) / rect.height, 2)
            let y = view.isFlipped ? bounds.maxY - rect.maxY : rect.minY - bounds.minY
            let destination = CGRect(
                x: (rect.minX - bounds.minX) * 2, y: y * 2,
                width: rect.width * 2, height: rect.height * 2)
            context.draw(try XCTUnwrap(tile.cgImage), in: destination)
            tiles.append(["requestedY": coveredY, "clipBounds": NSStringFromRect(clip.bounds),
                          "visibleRect": NSStringFromRect(view.visibleRect), "sourceRect": NSStringFromRect(rect),
                          "destinationPixels": NSStringFromRect(destination),
                          "pixels": [tile.pixelsWide, tile.pixelsHigh]])
            coveredY = rect.maxY
        }
        XCTAssertGreaterThanOrEqual(coveredY, bounds.maxY - 0.5, "All document tiles must be rendered")
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        bitmap.size = bounds.size
        renderNumber += 1
        if let directory = try diagnosticDirectory() {
            let metadata: [String: Any] = [
                "render": renderNumber, "documentClass": String(describing: type(of: view)),
                "documentBounds": NSStringFromRect(bounds), "documentIsFlipped": view.isFlipped,
                "clipClass": String(describing: type(of: clip)), "originalClipOrigin": NSStringFromPoint(originalOrigin),
                "windowBackingScale": view.window?.backingScaleFactor ?? 0, "pixels": [width, height], "tiles": tiles]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("render-\(renderNumber).json"))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("render-\(renderNumber).png"))
        }
        return bitmap
    }

    /// Waits until the document height stops changing, then saves the render as `capture` when the CI
    /// artifact directory is set. Height is what rows and disclosure state change, and it does not
    /// depend on how text renders.
    private func settle(_ document: NSView, capture name: String? = nil) async throws {
        let root = try XCTUnwrap(document.window?.contentView)
        var previous: CGFloat = -1
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            root.layoutSubtreeIfNeeded()
            let height = document.bounds.height
            if abs(height - previous) < 0.5 {
                if let name, ProcessInfo.processInfo.environment["PTB_SNAPSHOT_SCREENSHOT_DIR"] != nil {
                    try save(try await bitmap(of: document), name: name)
                }
                return
            }
            previous = height
            try await Task.sleep(for: .milliseconds(300))
        } while ContinuousClock.now < deadline
        XCTFail("Settings document height never settled: \(document.bounds.height)")
        throw URLError(.cannotParseResponse)
    }

    private func toggleHistory(in document: NSView, l: L, expanded: Bool) async throws {
        let root = try XCTUnwrap(document.window?.contentView)
        let deadline = ContinuousClock.now + .seconds(5)
        var buttons = [NSButton]()
        repeat {
            root.layoutSubtreeIfNeeded()
            buttons = descendants(root).compactMap { $0 as? NSButton }
            if let button = buttons.first(where: { $0.accessibilityIdentifier() == "snapshotHistory" }) {
                XCTAssertEqual(button.title, l.snapshotsSectionTitle)
                XCTAssertEqual(button.accessibilityLabel(), l.snapshotsSectionTitle)
                XCTAssertEqual(button.accessibilityValue() as? String, l.snapshotHistoryState(expanded: expanded))
                XCTAssertTrue(button.isEnabled, "Snapshot history must remain actionable")
                button.scrollToVisible(button.bounds)
                button.performClick(nil)
                try await Task.sleep(for: .milliseconds(200))
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        let diagnostic = buttons.map {
            "title=\($0.title), label=\(String(describing: $0.accessibilityLabel())), identifier=\(String(describing: $0.accessibilityIdentifier()))"
        }.joined(separator: "\n")
        XCTFail("Missing native snapshot history button: \(l.snapshotsSectionTitle)\n\(diagnostic)")
        throw URLError(.cannotParseResponse)
    }

    private func save(_ rendered: NSBitmapImageRep, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_SNAPSHOT_SCREENSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(rendered.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
