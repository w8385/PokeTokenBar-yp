import XCTest
import AppKit
@testable import PokeTokenBar

// Sprites must keep their source aspect ratio in every frame that draws them.
//
// Root cause of the regression this guards: both render paths forced the sprite into a *square*
// box — `SpriteView` used `.resizable().frame(width: size, height: size)` with no aspect mode, and
// `menuBarImage` drew into `NSRect(width: h - 2, height: h - 2)`. Stretching to fill a square is
// only invisible when the source is already square, and every *static* asset is: PokeAPI species
// PNGs are 96×96, item PNGs are 30×30. The Gen-V animated GIFs are not — their canvases are cropped
// per species (Spoink #325 is 36×66, Pikachu #25 is 50×46, Gengar #143 is 74×75) — so the defect
// only ever surfaced on the animated path, which is exactly the path no test measured.
//
// These cases pin the geometry rather than the pixels: `fittedSize` is the single source of truth
// both call sites now go through, so one guard covers the popover and the menu bar together.
final class SpriteAspectRatioTests: XCTestCase {

    /// Real canvas sizes, straight off the PokeAPI sprite sheets these views load.
    private static let spoinkGIF = CGSize(width: 36, height: 66)    // tall — worst distortion
    private static let pikachuGIF = CGSize(width: 50, height: 46)   // wide
    private static let gengarGIF = CGSize(width: 74, height: 75)    // near-square
    private static let staticPNG = CGSize(width: 96, height: 96)    // square — the silent case
    private static let swannaGIF = CGSize(width: 137, height: 69)   // wings spread — very wide
    private static let tynamoGIF = CGSize(width: 57, height: 19)    // widest ratio

    // MARK: Aspect fit

    /// The trigger, stated as the property that used to fail: a non-square source must not come out
    /// square. Without this, the assertions below could all pass on a source that was square anyway.
    func testNonSquareSpriteDoesNotRenderSquare() {
        let fit = SpriteFit.size(for: Self.spoinkGIF, box: 84)
        XCTAssertNotEqual(fit.width, fit.height, accuracy: 0.01,
                          "a 36×66 sprite rendered square is the defect — it is 1.83× too wide")
    }

    /// Source ratio is preserved exactly, for tall, wide and near-square canvases alike.
    func testFittedSizePreservesSourceAspectRatio() {
        for source in [Self.spoinkGIF, Self.pikachuGIF, Self.gengarGIF, Self.staticPNG] {
            for box in [22.0, 40.0, 76.0, 84.0, 96.0] as [CGFloat] {
                let fit = SpriteFit.size(for: source, box: box)
                XCTAssertEqual(fit.width / fit.height, source.width / source.height, accuracy: 0.001,
                               "source=\(source) box=\(box)")
            }
        }
    }

    /// Fit, not fill — the sprite stays inside the box on both axes and touches the longer one.
    func testFittedSizeFillsTheBoxOnItsLongerAxisAndNeverOverflows() {
        for source in [Self.spoinkGIF, Self.pikachuGIF, Self.gengarGIF, Self.staticPNG] {
            let fit = SpriteFit.size(for: source, box: 84)
            XCTAssertLessThanOrEqual(fit.width, 84.001, "source=\(source)")
            XCTAssertLessThanOrEqual(fit.height, 84.001, "source=\(source)")
            XCTAssertEqual(max(fit.width, fit.height), 84, accuracy: 0.001,
                           "the longer axis must reach the box — anything less is under-scaled")
        }
    }

    /// Square sources must be untouched, so the static popover/dex/item art does not shift.
    func testSquareSourceStillFillsTheSquareBox() {
        let fit = SpriteFit.size(for: Self.staticPNG, box: 84)
        XCTAssertEqual(fit.width, 84, accuracy: 0.001)
        XCTAssertEqual(fit.height, 84, accuracy: 0.001)
    }

    /// A zero/empty source (undecodable image) falls back to the box instead of dividing by zero.
    func testDegenerateSourceFallsBackToBoxWithoutDividingByZero() {
        for bad in [CGSize.zero, CGSize(width: 0, height: 66), CGSize(width: 36, height: 0)] {
            let fit = SpriteFit.size(for: bad, box: 22)
            XCTAssertEqual(fit.width, 22, accuracy: 0.001, "source=\(bad)")
            XCTAssertEqual(fit.height, 22, accuracy: 0.001, "source=\(bad)")
        }
    }

    // MARK: Menu bar canvas

    /// The menu bar canvas is 22pt tall always, and only as wide as the fitted sprite (+1pt padding
    /// per side). A fixed 22×22 canvas would pad a tall sprite with dead space that pushes the usage
    /// number away from it.
    func testMenuBarCanvasTracksFittedWidthAndKeepsFixedHeight() {
        let tall = AppDelegate.menuBarLayout(for: Self.spoinkGIF, up: false)
        XCTAssertEqual(tall.canvas.height, 22, accuracy: 0.001)
        XCTAssertEqual(tall.rect.height, 20, accuracy: 0.001, "tall sprite fills the 20pt content box")
        XCTAssertEqual(tall.rect.width, 20 * (36.0 / 66.0), accuracy: 0.001)
        XCTAssertEqual(tall.canvas.width, tall.rect.width + 2, accuracy: 0.001)
        XCTAssertLessThan(tall.canvas.width, 22, "a 36×66 sprite must not claim the full square width")

        let wide = AppDelegate.menuBarLayout(for: Self.pikachuGIF, up: false)
        XCTAssertEqual(wide.rect.height, 20, accuracy: 0.001, "wide sprite fills the 20pt height too")
        XCTAssertEqual(wide.rect.width, 20 * (50.0 / 46.0), accuracy: 0.001)
        XCTAssertEqual(wide.canvas.width, wide.rect.width + 2, accuracy: 0.001)
        XCTAssertEqual(wide.canvas.height, 22, accuracy: 0.001, "height is fixed so the baseline cannot jitter")
    }

    /// The trigger: a wide canvas sized by a 20pt square comes out half height (Swanna 10pt tall).
    /// It must fill the height and only give way once it reaches the width cap.
    func testWideSpriteFillsMenuBarHeightUntilTheWidthCap() {
        let cap = AppDelegate.menuBarSpriteMaxWidth
        let swanna = AppDelegate.menuBarLayout(for: Self.swannaGIF, up: false)
        XCTAssertGreaterThan(swanna.rect.height, 15,
                             "137×69 fitted to a 20pt square is 10pt tall — the defect")
        XCTAssertEqual(swanna.rect.width, min(cap, 20 * (137.0 / 69.0)), accuracy: 0.001)
        XCTAssertEqual(swanna.rect.width / swanna.rect.height, 137.0 / 69.0, accuracy: 0.001)

        let tynamo = AppDelegate.menuBarLayout(for: Self.tynamoGIF, up: false)
        XCTAssertEqual(tynamo.rect.width, cap, accuracy: 0.001, "the widest ratio stops at the cap")
        XCTAssertEqual(tynamo.rect.height, cap * (19.0 / 57.0), accuracy: 0.001)
        XCTAssertEqual(tynamo.canvas.width, cap + 2, accuracy: 0.001)
        XCTAssertEqual(tynamo.canvas.height, 22, accuracy: 0.001)
    }

    /// Square static sprites keep the exact pre-fix menu bar geometry (22×22 canvas, 20×20 at x=1).
    func testMenuBarGeometryUnchangedForSquareSprites() {
        let layout = AppDelegate.menuBarLayout(for: Self.staticPNG, up: false)
        XCTAssertEqual(layout.canvas, NSSize(width: 22, height: 22))
        XCTAssertEqual(layout.rect, NSRect(x: 1, y: 0, width: 20, height: 20))
    }

    /// The bob offset still lifts the sprite by 1pt, and the sprite stays inside the canvas.
    func testBobOffsetLiftsSpriteAndStaysInsideCanvas() {
        for source in [Self.spoinkGIF, Self.pikachuGIF, Self.staticPNG, Self.swannaGIF, Self.tynamoGIF] {
            let down = AppDelegate.menuBarLayout(for: source, up: false)
            let up = AppDelegate.menuBarLayout(for: source, up: true)
            XCTAssertEqual(up.rect.minY - down.rect.minY, 1, accuracy: 0.001, "source=\(source)")
            XCTAssertLessThanOrEqual(up.rect.maxY, up.canvas.height + 0.001, "source=\(source)")
            XCTAssertLessThanOrEqual(up.rect.maxX, up.canvas.width + 0.001, "source=\(source)")
            XCTAssertGreaterThanOrEqual(down.rect.minX, 0, "source=\(source)")
        }
    }

    // MARK: Rendered images

    /// End-to-end on the drawing path: the composed menu bar image carries the fitted, not squared,
    /// canvas. Guards against the layout being computed correctly but ignored by the draw call.
    @MainActor
    func testComposedMenuBarImageUsesFittedCanvas() {
        let sprite = Self.solidImage(size: Self.spoinkGIF)
        let composed = AppDelegate.menuBarImage(from: sprite, up: false)
        let expected = AppDelegate.menuBarLayout(for: Self.spoinkGIF, up: false).canvas
        XCTAssertEqual(composed.size.width, expected.width, accuracy: 0.001)
        XCTAssertEqual(composed.size.height, expected.height, accuracy: 0.001)
    }

    /// Menu bar frames are handed to `spriteLayer.contents`, which is what keeps a frame swap off the
    /// view drawing path (measured 2.00ms -> 0.27ms per frame). If the conversion ever returns nil,
    /// `setStatusImage` falls back to `button.image` and that saving disappears **silently** — the
    /// animation still looks correct, so nothing but this test would catch it.
    @MainActor
    func testMenuBarFramesConvertToLayerBitmaps() {
        for source in [Self.spoinkGIF, Self.pikachuGIF, Self.staticPNG] {
            for up in [false, true] {
                let composed = AppDelegate.menuBarImage(from: Self.solidImage(size: source), up: up)
                guard let bitmap = AppDelegate.cgFrame(from: composed) else {
                    XCTFail("cgFrame nil for \(source) up=\(up) — the layer path would fall back")
                    continue
                }
                XCTAssertGreaterThanOrEqual(CGFloat(bitmap.width), composed.size.width - 0.001,
                                           "bitmap must hold at least 1 pixel per point (source=\(source))")
            }
        }
        // Fault injection: the assertion above is only meaningful if the conversion *can* fail.
        // An empty image has no representation to rasterize, so nil is reachable.
        XCTAssertNil(AppDelegate.cgFrame(from: NSImage(size: .zero)),
                     "if this ever converts, the guard above stopped being able to fail")
    }

    /// `contentsScale` must follow the bitmap's own pixel/point density, not the current screen.
    /// Frames are baked by `lockFocus` at the backing scale in effect when they were composed, so
    /// reading the scale off the screen would double the sprite after a move to a 1x display.
    func testSpriteContentsScaleFollowsTheBitmapNotTheScreen() {
        XCTAssertEqual(AppDelegate.spriteContentsScale(pixelWidth: 44, pointWidth: 22), 2, accuracy: 0.001)
        XCTAssertEqual(AppDelegate.spriteContentsScale(pixelWidth: 22, pointWidth: 22), 1, accuracy: 0.001)
        // A zero-width canvas must not yield 0 (a 0 scale makes the layer vanish) or divide by zero.
        XCTAssertEqual(AppDelegate.spriteContentsScale(pixelWidth: 0, pointWidth: 0), 1, accuracy: 0.001)
    }

    /// `SpriteView` sizes its image through the same helper, so the popover header, evolution line
    /// and dex thumbnails cannot drift from the menu bar.
    @MainActor
    func testSpriteViewImageSizeMatchesFittedSize() {
        let rendered = SpriteView.imageSize(for: Self.solidImage(size: Self.spoinkGIF), box: 76)
        XCTAssertEqual(rendered.width, SpriteFit.size(for: Self.spoinkGIF, box: 76).width, accuracy: 0.001)
        XCTAssertEqual(rendered.height, 76, accuracy: 0.001)
        XCTAssertLessThan(rendered.width, 76, "a tall sprite must be narrower than its square slot")
    }

    private static let megaCharizardXStatic = CGSize(width: 89, height: 82)
    private static let megaCharizardXGIF = CGSize(width: 161, height: 107)

    func testAWidePoseIsScaledUpToStandAsTallAsItsStaticArt() {
        let box = SpriteFit.contentBox(76)
        let plain = SpriteFit.size(for: Self.megaCharizardXGIF, box: box)
        let scaled = SpriteFit.animatedSize(for: Self.megaCharizardXGIF, reference: Self.megaCharizardXStatic, box: box)
        let staticHeight = SpriteFit.size(for: Self.megaCharizardXStatic, box: box).height
        XCTAssertLessThan(plain.height, staticHeight * 0.85, "the plain fit is the problem being fixed")
        XCTAssertEqual(scaled.height, staticHeight, accuracy: staticHeight * 0.15)
        XCTAssertGreaterThan(scaled.height, plain.height)
    }

    func testAScaledUpWidePoseGrowsAtMost40PercentWider() {
        let box = SpriteFit.contentBox(96)
        let gif = CGSize(width: 178, height: 95)
        let plain = SpriteFit.size(for: gif, box: box)
        let scaled = SpriteFit.animatedSize(for: gif, reference: CGSize(width: 77, height: 77), box: box)
        XCTAssertEqual(scaled.width, plain.width * 1.4, accuracy: 0.001)
        XCTAssertEqual(scaled.width / scaled.height, gif.width / gif.height, accuracy: 0.001, "the pose keeps its proportions")
    }

    func testAnAnimatedCropIsNeverShrunkOrChangedWhenItIsCloseEnough() {
        let box = SpriteFit.contentBox(76)
        let closeEnough = CGSize(width: 98, height: 101)
        XCTAssertEqual(SpriteFit.animatedSize(for: closeEnough, reference: CGSize(width: 68, height: 70), box: box),
                       SpriteFit.size(for: closeEnough, box: box))
        let tall = CGSize(width: 47, height: 64)
        XCTAssertEqual(SpriteFit.animatedSize(for: tall, reference: CGSize(width: 40, height: 40), box: box),
                       SpriteFit.size(for: tall, box: box), "a taller animation than its static stays as it is")
    }

    func testWithoutAUsableReferenceTheAnimatedCropKeepsThePlainFit() {
        let box = SpriteFit.contentBox(76)
        let plain = SpriteFit.size(for: Self.megaCharizardXGIF, box: box)
        XCTAssertEqual(SpriteFit.animatedSize(for: Self.megaCharizardXGIF, reference: nil, box: box), plain)
        XCTAssertEqual(SpriteFit.animatedSize(for: Self.megaCharizardXGIF, reference: .zero, box: box), plain)
    }

    private static let vanilliteGIF = CGSize(width: 55, height: 45)
    private static let vanilliteStatic = CGSize(width: 24, height: 36)
    /// Frames 0-36 hold the body at x 30..53; the bubbles that widen the union show in a minority of frames.
    private static let vanilliteBody: ClosedRange<CGFloat> = (30.0 / 55)...(54.0 / 55)

    func testAScaledUpPoseNeverReachesPastTheSlotWithItsBody() {
        let box = SpriteFit.contentBox(76)
        let scaled = SpriteFit.animatedSize(for: Self.vanilliteGIF, reference: Self.vanilliteStatic, box: box,
                                            body: Self.vanilliteBody)
        let plain = SpriteFit.size(for: Self.vanilliteGIF, box: box)
        let bodyRight = scaled.width * (Self.vanilliteBody.upperBound - 0.5)
        XCTAssertLessThanOrEqual(bodyRight, box / 2 + 0.001, "the body's right edge stays inside the slot")
        XCTAssertGreaterThanOrEqual(scaled.width, plain.width, "the cap never shrinks below the plain fit")
        XCTAssertGreaterThan(scaled.width, plain.width, "the body has a little room left, so it still grows to it")
    }

    func testABodyThatFitsKeepsTheFullScaleUp() {
        let box = SpriteFit.contentBox(76)
        let uncapped = SpriteFit.animatedSize(for: Self.megaCharizardXGIF, reference: Self.megaCharizardXStatic, box: box)
        let withBody = SpriteFit.animatedSize(for: Self.megaCharizardXGIF, reference: Self.megaCharizardXStatic,
                                              box: box, body: 0.2...0.8)
        XCTAssertEqual(withBody, uncapped)
        XCTAssertGreaterThan(withBody.height, SpriteFit.size(for: Self.megaCharizardXGIF, box: box).height)
    }

    @MainActor
    func testTheBodySpanIsTheMedianFrameNotTheFrameThatFlaresOut() throws {
        func frame(_ columns: ClosedRange<Int>) -> NSImage {
            let image = NSImage(size: NSSize(width: 10, height: 4))
            image.lockFocus()
            NSColor.red.setFill()
            NSRect(x: columns.lowerBound, y: 0, width: columns.count, height: 4).fill()
            image.unlockFocus()
            return image
        }
        let frames = [frame(6...9), frame(6...9), frame(0...9), frame(6...9)]
        let span = try XCTUnwrap(SpriteBody.span(first: frames[0]) { frames })
        XCTAssertEqual(span.lowerBound, 0.6, accuracy: 0.001)
        XCTAssertEqual(span.upperBound, 1.0, accuracy: 0.001)
        XCTAssertNil(SpriteBody.span(first: frame(0...9)) { [frame(0...9)] }, "a still has no animation to measure")
    }

    func testTheBubbleAnchorFollowsTheBodyCappedSize() {
        let uncapped = SpriteVisibleTop.inset(box: 76, imageSize: Self.vanilliteGIF, opaqueTopFraction: 0,
                                              reference: Self.vanilliteStatic)
        let capped = SpriteVisibleTop.inset(box: 76, imageSize: Self.vanilliteGIF, opaqueTopFraction: 0,
                                            reference: Self.vanilliteStatic, body: Self.vanilliteBody)
        XCTAssertGreaterThan(capped, uncapped, "a less scaled pose is shorter, so its top sits lower")
    }

    func testTheBubbleAnchorFollowsTheScaledUpPose() {
        let plain = SpriteVisibleTop.inset(box: 76, imageSize: Self.megaCharizardXGIF, opaqueTopFraction: 0)
        let scaled = SpriteVisibleTop.inset(box: 76, imageSize: Self.megaCharizardXGIF, opaqueTopFraction: 0,
                                            reference: Self.megaCharizardXStatic)
        XCTAssertLessThan(scaled, plain, "a taller sprite has its visible top closer to the box top")
    }

    private static func solidImage(size: CGSize) -> NSImage {
        let img = NSImage(size: NSSize(width: size.width, height: size.height))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.unlockFocus()
        return img
    }
}
