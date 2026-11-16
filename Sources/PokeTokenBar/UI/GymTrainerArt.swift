import AppKit
import SwiftUI

/// The pixel-art trainers, one PNG per battle id (`assets/trainers/<id>.png`), copied into the app bundle's
/// `Resources/trainers` by `scripts/build-app.sh`.
@MainActor
enum GymTrainerArt {
    /// Where the PNGs are. Tests that render a trainer point it at the repository's `assets/trainers`.
    static var directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("trainers")
    private static var cache: [String: NSImage] = [:]

    static func image(_ battleID: String) -> NSImage? {
        if let cached = cache[battleID] { return cached }
        guard let file = directory?.appendingPathComponent("\(battleID).png"),
              let image = NSImage(contentsOf: file) else { return nil }
        cache[battleID] = image
        return image
    }

    static func clearCache() { cache = [:] }
}

/// A trainer's sprite, drawn without smoothing so the pixels stay sharp; a plain silhouette when the art is missing.
@MainActor
struct TrainerSprite: View {
    let battleID: String
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let image = GymTrainerArt.image(battleID) {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
            } else {
                Image(systemName: "person.fill").resizable().scaledToFit().padding(size * 0.2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
