import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// How a production view lays itself out, read from SwiftUI's own layout and not from pixels. The
/// view decides its own `ViewThatFits` branch on the machine that runs the test, so nothing here
/// depends on a pixel budget or on how a font renders. Tests must not read rendered text with
/// OCR; `NoOCRInTestsGuardTests` fails the build when one does.
@MainActor
enum LayoutMeasure {
    private static let unbounded: CGFloat = 100_000

    /// The size `view` takes when offered `width`. `nil` offers unlimited width: the ideal size.
    static func size<V: View>(_ view: V, width: CGFloat? = nil) -> CGSize {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width ?? unbounded, height: unbounded))
    }

    /// Fails when a row of labels that may stack (`ViewThatFits`) overflows `width`, or when any label
    /// wraps. Side by side it must be exactly one line tall; stacked, below three lines.
    static func assertLabelsNeverWrap<V: View>(_ row: V, within width: CGFloat, _ message: String = "",
                                               file: StaticString = #filePath, line: UInt = #line) {
        let ideal = size(row)
        let offered = size(row, width: width)
        XCTAssertLessThanOrEqual(offered.width, width + 0.5,
                                 "\(message) overflows: \(offered.width)pt in \(width)pt",
                                 file: file, line: line)
        if ideal.width <= width + 0.5 {
            XCTAssertEqual(offered.height, ideal.height, accuracy: 0.5,
                           "\(message) fits on one row but is \(offered.height)pt tall, one line is \(ideal.height)pt",
                           file: file, line: line)
        } else {
            XCTAssertLessThan(offered.height, ideal.height * 3,
                              "\(message) stacked but a label wraps: \(offered.height)pt, one line is \(ideal.height)pt",
                              file: file, line: line)
        }
    }
}

/// The controls SwiftUI backs with native views, read from the AppKit tree: button titles, accessibility
/// labels and tooltips. Plain `Text` has no native view, so it is checked at its string source instead.
@MainActor
enum NativeControls {
    @MainActor
    struct Snapshot {
        let host: NSView
        let buttons: [NSButton]
        var labels: [String] {
            buttons.flatMap { [$0.title, $0.accessibilityLabel() ?? "", $0.toolTip ?? ""] }.filter { !$0.isEmpty }
        }
        func has(_ text: String) -> Bool { labels.contains(text) }
    }

    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    static func snapshot<V: View>(of view: V, width: CGFloat = PopoverMetrics.contentWidth,
                                  height: CGFloat = 700) async throws -> Snapshot {
        let host = OffscreenRender.host(
            view.frame(width: width).environment(\.colorScheme, .light),
            size: CGSize(width: width, height: height), appearance: .aqua)
        try await OffscreenRender.settle(host, for: .milliseconds(400))
        return Snapshot(host: host, buttons: descendants(host).compactMap { $0 as? NSButton })
    }
}
