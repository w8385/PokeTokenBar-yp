import AppKit
import SwiftUI
import XCTest

/// Reaching it means a hang. A slow machine never gets near it, so no test waits for a duration.
let waitCeilingSeconds: TimeInterval = 60
let waitCeiling: Duration = .seconds(waitCeilingSeconds)

struct WaitTimedOut: Error, CustomStringConvertible {
    let description: String
}

/// The one wait in Tests: polls `condition`, letting the run loop and other tasks run between polls, until it
/// holds. A test proceeds when its condition holds, never after a duration. `OffscreenRenderGuardTests` fails
/// when another test file sleeps or spins the run loop for a fixed time.
func waitUntil(_ what: @autoclosure () -> String, isolation: isolated (any Actor)? = #isolation,
               file: StaticString = #filePath, line: UInt = #line,
               _ condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now + waitCeiling
    while true {
        if try await condition() { return }
        if ContinuousClock.now >= deadline {
            let message = "waited \(waitCeiling) for \(what())"
            XCTFail(message, file: file, line: line)
            throw WaitTimedOut(description: message)
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// The only place a test turns a view into pixels. `host` uses no window at all. `windowHosting` builds
/// one window, ordered in behind everything and off every screen; nothing here orders a window front,
/// makes one key or activates the app, so a screenshot run never touches the user's desktop.
/// `OffscreenRenderGuardTests` fails the build when another test file does any of that.
@MainActor
enum OffscreenRender {
    /// A hosting view with no window and no animations. `onAppear`, `.task`, `ScrollView` and AppKit-backed
    /// controls all work without one. Pass `appearance` to make `.primary` and system colors resolve the same
    /// way on every machine; the `colorScheme` environment alone does not reach AppKit controls.
    static func host<Content: View>(_ content: Content, size: CGSize,
                                    appearance: NSAppearance.Name? = nil) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(content.withoutAnimations()))
        host.frame = NSRect(origin: .zero, size: size)
        if let appearance { host.appearance = NSAppearance(named: appearance) }
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// `host` for tests that need the controller (`sizeThatFits`).
    static func controller<Content: View>(_ content: Content) -> NSHostingController<AnyView> {
        NSHostingController(rootView: AnyView(content.withoutAnimations()))
    }

    /// Lays `view` out until `ready` holds, then until its tree reads the same on three passes in a row.
    /// The tree is frames, native control state and accessibility text; pixels are not part of it, because
    /// animated sprites never stop changing them. A test that reads data-dependent content passes `ready`.
    static func settle(_ view: NSView, file: StaticString = #filePath, line: UInt = #line,
                       until ready: () throws -> Bool = { true }) async throws {
        try await waitUntil("\(type(of: view)) to be ready", in: view, file: file, line: line, ready)
        var previous = ""
        var unchanged = 0
        try await waitUntil("\(type(of: view)) to stop changing: \(previous.prefix(2_000))", in: view,
                            file: file, line: line) {
            let current = fingerprint(of: view)
            unchanged = current == previous ? unchanged + 1 : 0
            previous = current
            return unchanged >= 2
        }
    }

    /// `waitUntil` that lays `view` out before every poll.
    static func waitUntil(_ what: @autoclosure () -> String, in view: NSView,
                          file: StaticString = #filePath, line: UInt = #line,
                          _ condition: () throws -> Bool) async throws {
        try await PokeTokenBarTests.waitUntil(what(), file: file, line: line) {
            view.window?.contentView?.layoutSubtreeIfNeeded()
            view.layoutSubtreeIfNeeded()
            return try condition()
        }
    }

    /// Waits until two bitmaps in a row are identical. Only for views with nothing animating in them.
    static func stableBitmap(of view: NSView, scale: CGFloat = 2,
                             file: StaticString = #filePath, line: UInt = #line) async throws -> NSBitmapImageRep {
        view.window?.displayIfNeeded()
        var previous = try bitmap(of: view, scale: scale)
        var current = previous
        try await waitUntil("\(type(of: view)) pixels to stop changing", in: view, file: file, line: line) {
            view.window?.displayIfNeeded()
            current = try bitmap(of: view, scale: scale)
            defer { previous = current }
            return current.representation(using: .png, properties: [:]) == previous.representation(using: .png, properties: [:])
        }
        return current
    }

    static func fingerprint(of view: NSView) -> String {
        var lines: [String] = []
        func walk(_ node: NSView) {
            let frame = view.convert(node.bounds, from: node).integral
            var line = "\(type(of: node)) \(frame) \(node.isHidden)"
            if let control = node as? NSControl { line += " \(control.isEnabled) \(control.stringValue)" }
            if let button = node as? NSButton { line += " \(button.title) \(button.state.rawValue)" }
            if let image = node as? NSImageView { line += " \(image.image?.size ?? .zero)" }
            lines.append(line)
            node.subviews.forEach(walk)
        }
        walk(view)
        func accessibility(_ element: Any, depth: Int) {
            guard depth < 40, let element = element as? NSAccessibilityProtocol else { return }
            let value = element.accessibilityValue().map { "\($0)" } ?? ""
            lines.append("ax \(element.accessibilityRole()?.rawValue ?? "") \(element.accessibilityLabel() ?? "") \(value)")
            for child in element.accessibilityChildren() ?? [] { accessibility(child, depth: depth + 1) }
        }
        accessibility(view, depth: 0)
        return lines.joined(separator: "\n")
    }

    /// Bitmap of `view.bounds` at exactly `scale` pixels per point (2x by default, what the popover draws
    /// on a Retina screen), whatever display the machine has. Divide pixel counts by `scale` to get points.
    static func bitmap(of view: NSView, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        try fixedBitmap(of: view, scale: scale)
    }

    /// `bitmapImageRepForCachingDisplay` follows the main screen, so the same test saw 1x or 2x pixels
    /// depending on the display. This allocates the bitmap itself.
    static func fixedBitmap(of view: NSView, scale: CGFloat) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int((bounds.width * scale).rounded(.up)), pixelsHigh: Int((bounds.height * scale).rounded(.up)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        return bitmap
    }

    static func png(of view: NSView, scale: CGFloat = 1) throws -> Data {
        try XCTUnwrap(fixedBitmap(of: view, scale: scale).representation(using: .png, properties: [:]))
    }

    static func writePNG(of view: NSView, to file: URL, scale: CGFloat = 1) throws {
        try png(of: view, scale: scale).write(to: file)
    }

    /// Host, settle, write: the whole screenshot in one call.
    @discardableResult
    static func capture<Content: View>(_ content: Content, size: CGSize,
                                       appearance: NSAppearance.Name? = nil, scale: CGFloat = 1,
                                       to file: URL, file source: StaticString = #filePath, line: UInt = #line,
                                       until ready: () throws -> Bool = { true }) async throws -> Data {
        let host = host(content, size: size, appearance: appearance)
        try await settle(host, file: source, line: line, until: ready)
        let data = try png(of: host, scale: scale)
        try data.write(to: file)
        return data
    }

    /// For the few tests that deliver events or need real window layout. The window sits behind
    /// everything at (-10000, -10000) on no screen, is never key or main, and the process stays
    /// `.prohibited`, so it cannot come to the front or take focus. The caller owns it and calls
    /// `close()` when done.
    static func windowHosting(_ view: NSView, appearance: NSAppearance.Name? = nil) -> NSWindow {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: view.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let appearance { window.appearance = NSAppearance(named: appearance) }
        window.contentView = view
        window.orderBack(nil)
        return window
    }

    /// A left click at `point` (window coordinates) on a `windowHosting` window.
    static func click(at point: NSPoint, in window: NSWindow) throws {
        var button = window.contentView?.superview?.hitTest(point)
        while let current = button, !(current is NSButton) { button = current.superview }
        if let button = button as? NSButton {
            button.performClick(nil)
            return
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0)))
        }
    }
}

extension View {
    /// What every test host applies: state changes land in their final frame at once.
    func withoutAnimations() -> some View {
        transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
    }
}
