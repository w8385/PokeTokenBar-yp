import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

private struct SnapshotHistoryOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class SnapshotHistoryTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Drives the production Settings disclosure, including rows outside the scroll viewport.
@MainActor
final class SnapshotHistoryRenderingTests: XCTestCase {
    private var window: NSWindow?
    private var previousKeyWindow: NSWindow?
    private var renderNumber = 0

    override func tearDown() async throws {
        window?.close()
        window = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }

    func testTenSnapshotsStartCollapsedAndExpandAllRowsThenCollapseAndReopen() async throws {
        let (companion, usage) = try makeStores(snapshotCount: 10)
        let create = companion.l.createSnapshotButton
        let root = host(companion, usage)
        let document = try await settingsDocument(in: root)
        try await settle(document, rows: 0, present: [create], capture: "snapshots-collapsed")
        let collapsedHeight = document.bounds.height

        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await settle(document, rows: 10, present: [create], capture: "snapshots-expanded")
        XCTAssertGreaterThan(document.bounds.height, collapsedHeight + 200)
        XCTAssertEqual(companion.availableSnapshots.count, 10)

        try await toggleHistory(in: document, l: companion.l, expanded: true)
        try await settle(document, rows: 0, capture: "snapshots-collapsed-again")
        XCTAssertEqual(document.bounds.height, collapsedHeight, accuracy: 2)

        // Reopening Settings starts a new visit, even after leaving its history expanded.
        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await settle(document, rows: 10)
        window?.close()
        let reopened = host(companion, usage)
        let reopenedDocument = try await settingsDocument(in: reopened)
        try await settle(reopenedDocument, rows: 0, present: [create], capture: "snapshots-reopened")
        XCTAssertEqual(companion.availableSnapshots.count, 10)
    }

    func testEmptyHistoryIsDisclosedAndManualCreationRemainsAvailable() async throws {
        let (companion, usage) = try makeStores(snapshotCount: 0)
        let create = companion.l.createSnapshotButton
        let document = try await settingsDocument(in: host(companion, usage))
        let collapsedWords = try await settle(document, present: [create])
        XCTAssertFalse(collapsedWords.contains { $0.reads(companion.l.noSnapshotsYet) })

        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await settle(document, rows: 0, present: [companion.l.noSnapshotsYet, create],
                         capture: "snapshots-empty-expanded")
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
        _ = NSApplication.shared
        if previousKeyWindow == nil { previousKeyWindow = NSApp.keyWindow }
        let host = NSHostingView(rootView: SettingsView(onClose: {}, onChooseRepresentative: {})
            .environment(companion).environment(usage).environment(UpdateChecker())
            .environment(\.colorScheme, .light)
            .frame(width: PopoverMetrics.width))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.width, height: 460)
        let window = SnapshotHistoryTestWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: 460),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        self.window = window
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

    private struct Word {
        let candidates: [String]
        let confidences: [Float]
        /// Pixel coordinates in the complete image, with the origin at the top left.
        let bounds: CGRect
        static func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        func reads(_ wanted: String, exactly: Bool = false) -> Bool {
            let normalized = Self.normalized(wanted)
            return candidates.contains {
                let text = Self.normalized($0)
                return exactly ? text == normalized : text.contains(normalized)
            }
        }
        func duplicates(_ other: Word) -> Bool {
            let overlap = bounds.intersection(other.bounds)
            let smallerArea = min(bounds.width * bounds.height, other.bounds.width * other.bounds.height)
            let texts = Set(candidates.map(Self.normalized).filter { !$0.isEmpty })
            return !overlap.isNull && overlap.width * overlap.height > smallerArea * 0.5
                && abs(bounds.midY - other.bounds.midY) < min(bounds.height, other.bounds.height) * 0.5
                && !texts.isDisjoint(with: other.candidates.map(Self.normalized))
        }
        var diagnostic: [String: Any] {
            ["candidates": candidates, "confidences": confidences, "globalPixelBounds": NSStringFromRect(bounds)]
        }
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

    private func recognize(_ image: CGImage, crop: CGRect) throws -> [Word] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap {
            let candidates = $0.topCandidates(10)
            let box = $0.boundingBox
            // CGImage crops start at the top; Vision boxes start at the bottom of each crop.
            let global = CGRect(x: crop.minX + box.minX * crop.width,
                                y: crop.minY + (1 - box.maxY) * crop.height,
                                width: box.width * crop.width, height: box.height * crop.height)
            return candidates.isEmpty ? nil : Word(candidates: candidates.map(\.string),
                confidences: candidates.map(\.confidence), bounds: global)
        } ?? []
    }

    /// Top pixel row of the render to recognize: 150pt above the history toggle, which keeps the
    /// "Create snapshot" button and every row below it. Falls back to the whole page.
    private func backupSectionPixel(in view: NSView, imageHeight: Int) -> Int {
        guard let root = view.window?.contentView,
              let toggle = descendants(root).compactMap({ $0 as? NSButton })
                  .first(where: { $0.accessibilityIdentifier() == "snapshotHistory" }) else { return 0 }
        let frame = view.convert(toggle.bounds, from: toggle)
        let top = view.isFlipped ? frame.minY - view.bounds.minY : view.bounds.maxY - frame.maxY
        return max(0, min(imageHeight, Int(((top - 150) * 2).rounded(.down))))
    }

    private struct Render {
        let words: [Word]
        let bitmap: NSBitmapImageRep
        let documentBounds: CGRect
    }

    private func render(_ view: NSView) async throws -> Render {
        let rendered = try await bitmap(of: view)
        let image = try XCTUnwrap(rendered.cgImage)
        let directory = try diagnosticDirectory()
        // Use native pixels without resizing. A 48pt overlap keeps row labels intact at crop
        // boundaries; global geometry merges only observations of the same physical label.
        let stripHeight = min(image.height, Int((try XCTUnwrap(view.enclosingScrollView).contentView.bounds.height * 2).rounded(.up)))
        let overlap = min(96, stripHeight / 4)
        // Everything above the backup section is unrelated Settings; reading it only costs OCR time.
        let firstPixel = backupSectionPixel(in: view, imageHeight: image.height)
        var y = firstPixel
        var result = [Word]()
        var strips = [[String: Any]]()
        while y < image.height {
            let crop = CGRect(x: 0, y: y, width: image.width, height: min(stripHeight, image.height - y))
            let words = try recognize(try XCTUnwrap(image.cropping(to: crop)), crop: crop)
            strips.append(["cropPixels": NSStringFromRect(crop), "words": words.map(\.diagnostic)])
            for word in words {
                if let index = result.firstIndex(where: { $0.duplicates(word) }) {
                    if (word.confidences.first ?? 0) > (result[index].confidences.first ?? 0) { result[index] = word }
                } else { result.append(word) }
            }
            if crop.maxY >= CGFloat(image.height) { break }
            y += stripHeight - overlap
        }
        if let directory {
            let metadata: [String: Any] = ["render": renderNumber, "firstOCRPixel": firstPixel,
                                         "strips": strips, "merged": result.map(\.diagnostic)]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("ocr-\(renderNumber).json"))
        }
        return Render(words: result, bitmap: rendered, documentBounds: view.bounds)
    }

    /// Renders the document until `rows` Restore rows (when given) and every `present` text are read
    /// from the same render, so one OCR pass checks the whole screen. The render that matched is
    /// saved as `capture`, re-rendered only if the layout moved while it settled.
    @discardableResult
    private func settle(_ document: NSView, rows: Int? = nil, present: [String] = [],
                        capture name: String? = nil) async throws -> [Word] {
        let deadline = ContinuousClock.now + .seconds(5)
        var problem = ""
        repeat {
            document.window?.contentView?.layoutSubtreeIfNeeded()
            let rendered = try await render(document)
            let actual = rendered.words.filter { $0.reads("Restore", exactly: true) }.count
            let missing = present.filter { text in !rendered.words.contains { $0.reads(text) } }
            problem = "restore rows expected \(rows.map(String.init) ?? "any"), rendered \(actual); missing text \(missing)"
            if (rows == nil || actual == rows) && missing.isEmpty {
                try await Task.sleep(for: .milliseconds(300))
                document.window?.contentView?.layoutSubtreeIfNeeded()
                let final = document.bounds == rendered.documentBounds ? rendered : try await render(document)
                if let name { try save(final.bitmap, name: name) }
                return final.words
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        XCTFail("Snapshot history never settled: \(problem)")
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
