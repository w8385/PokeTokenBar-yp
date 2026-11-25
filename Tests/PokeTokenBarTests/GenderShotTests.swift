import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class GenderShotTests: XCTestCase {
    private struct Subject {
        let id: String
        let speciesID: Int
        let gender: PokemonGender
        let label: String
    }

    private static let subjects = [
        Subject(id: "gyarados-m", speciesID: 130, gender: .male, label: "Gyarados ♂"),
        Subject(id: "gyarados-f", speciesID: 130, gender: .female, label: "Gyarados ♀"),
        Subject(id: "eevee-f", speciesID: 133, gender: .female, label: "Eevee ♀"),
        Subject(id: "indeedee-m", speciesID: 876, gender: .male, label: "Indeedee ♂"),
        Subject(id: "indeedee-f", speciesID: 876, gender: .female, label: "Indeedee ♀"),
    ]

    func testCaptureGenderArtAndBoxPages() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GENDER_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_GENDER_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for subject in Self.subjects {
            for animated in [false, true] {
                _ = await SpriteStore.shared.data(speciesID: subject.speciesID, animated: animated,
                                                  female: subject.gender == .female)
            }
        }
        let (store, cleanup) = try BoxDexFixture.makeStore(language: .en, mutate: { state in
            for subject in Self.subjects {
                var profile = PokemonProfile.generate(seed: UInt64(subject.speciesID), instanceID: subject.id)
                profile.gender = subject.gender
                profile.level = 40
                state.dex.append(DexEntry(id: subject.id, baseID: subject.speciesID, finalID: subject.speciesID,
                                          chainOrder: [subject.speciesID], rarity: .rare,
                                          caughtAt: Date(timeIntervalSince1970: 1_700_000_900), profile: profile,
                                          names: [subject.speciesID: try! SpeciesFacts.names(subject.speciesID)]))
            }
        })
        defer { cleanup() }
        for subject in Self.subjects { await store.loadPokemonDetails(speciesID: subject.speciesID) }

        try await write(spriteGrid, size: CGSize(width: 300, height: 580), to: directory.appendingPathComponent("sprites.png"))
        for subject in Self.subjects where subject.speciesID == 876 {
            let individual = try XCTUnwrap(store.boxIndividual(id: subject.id))
            let page = BoxDetailView(store: store, individual: individual, navigation: PopoverNavigation(), onBack: {},
                                     initialMiracle: nil)
                .environment(BattleEntryStore(defaults: UserDefaults(suiteName: "gender-shot-\(UUID())")!))
                .environment(store)
                .padding(PopoverMetrics.padding)
            try await write(page, size: CGSize(width: PopoverMetrics.width, height: 700),
                            to: directory.appendingPathComponent("box-\(subject.id).png"))
        }
    }

    private var spriteGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text("Still").font(.caption)
                Text("Animated").font(.caption)
            }
            ForEach(Self.subjects, id: \.id) { subject in
                GridRow {
                    Text(subject.label).font(.caption)
                    SpriteView(speciesID: subject.speciesID, size: 96, female: subject.gender == .female)
                    SpriteView(speciesID: subject.speciesID, size: 96, animated: true,
                               female: subject.gender == .female)
                }
            }
        }
        .padding(12)
    }

    private func write<V: View>(_ view: V, size: CGSize, to file: URL) async throws {
        let host = OffscreenRender.host(
            view.frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .dark)
                .environment(\.animatesSprites, false),
            size: size, appearance: .darkAqua)
        try await OffscreenRender.settle(host)
        _ = try await OffscreenRender.stableBitmap(of: host)
        try OffscreenRender.writePNG(of: host, to: file, scale: 2)
    }
}
