import AppKit
import SwiftUI
import XCTest

/// The only place a test turns a view into pixels. `host` uses no window at all. `windowHosting` builds
/// one window, ordered in behind everything and off every screen; nothing here orders a window front,
/// makes one key or activates the app, so a screenshot run never touches the user's desktop.
/// `OffscreenRenderGuardTests` fails the build when another test file does any of that.
@MainActor
enum OffscreenRender {
    /// A hosting view with no window. `onAppear`, `.task`, `ScrollView` and AppKit-backed controls all
    /// work without one. Pass `appearance` to make `.primary` and system colors resolve the same way
    /// on every machine; the `colorScheme` environment alone does not reach AppKit controls.
    static func host<Content: View>(_ content: Content, size: CGSize,
                                    appearance: NSAppearance.Name? = nil) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: size)
        if let appearance { host.appearance = NSAppearance(named: appearance) }
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// Lets `.task` / async image loads finish, then lays the view out once more.
    static func settle(_ view: NSView, for duration: Duration = .milliseconds(300)) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: duration)
        view.layoutSubtreeIfNeeded()
    }

    /// 1x bitmap of `view.bounds` (at the main screen's scale), or 2x with `scale: 2` (what the popover
    /// draws on a Retina screen). Pixel assertions keep this form; PNG output uses `fixedBitmap`.
    static func bitmap(of view: NSView, scale: CGFloat = 1) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        if scale == 1 {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: bounds))
            view.cacheDisplay(in: bounds, to: bitmap)
            return bitmap
        }
        return try fixedBitmap(of: view, scale: scale)
    }

    /// Bitmap of exactly `scale` pixels per point. `bitmapImageRepForCachingDisplay` follows the main
    /// screen, so the same test wrote 1x or 2x PNGs depending on whether a display was awake.
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
                                       settle duration: Duration = .milliseconds(300),
                                       to file: URL) async throws -> Data {
        let host = host(content, size: size, appearance: appearance)
        try await settle(host, for: duration)
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
