import SwiftUI
import XCTest
@testable import PokeTokenBar

private final class CountingFlavor: SpeciesFlavorProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var asked = 0

    var calls: Int { lock.withLock { asked } }

    func flavor(speciesID: Int) async -> SpeciesFlavor? {
        lock.withLock { asked += 1 }
        return nil
    }
}

@MainActor
final class SpeciesFlavorLoadTests: XCTestCase {
    func testTheFlavorLoadsWithCriesTurnedOff() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "flavor-cry-off-\(UUID())"))
        defaults.set(false, forKey: CryPlayer.enabledKey)
        let provider = CountingFlavor()
        let page = VStack { Text("Bulbasaur"); SpeciesFlavorCard(speciesID: 1, language: .en, provider: provider) }
        let host = OffscreenRender.host(page.defaultAppStorage(defaults), size: CGSize(width: 320, height: 200))
        try await OffscreenRender.settle(host) { provider.calls > 0 }
    }
}
