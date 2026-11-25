import XCTest

final class FormDisplayScanTests: XCTestCase {
    private let ui = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/PokeTokenBar/UI")

    /// Sprites that draw no individual: placeholders, fixed art, unowned species, prize eggs and bot gym ids,
    /// which carry no gender.
    private static let spritesWithoutAnIndividual: Set<String> = [
        "BagView.swift|speciesID: 143, size: 96, animated: true",
        "BagView.swift|speciesID: speciesID, size: 30, animated: false, shiny: true",
        "BoxView.swift|speciesID: nil, size: 32, animated: false",
        "BoxView.swift|speciesID: 25, size: 96, animated: true",
        "CompanionView.swift|speciesID: 25, size: 96, animated: true",
        "GymReplayView.swift|speciesID: id, size: 64, shiny: fighter.shiny, back: back",
        "GymResultView.swift|speciesID: spriteID, size: 36, shiny: fighter.shiny",
        "SettingsView.swift|speciesID: nil, size: 28",
        "ShopView.swift|speciesID: nil, size: 26",
        "UnownedSpeciesDetailView.swift|speciesID: species.id, size: 104, animated: true, spriteStore: spriteStore",
    ]

    func testEverySpriteOfAnIndividualPassesItsGender() throws {
        let call = try NSRegularExpression(pattern: #"\b(SpriteView|SpriteLoader\.image)\("#)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        var calls = 0
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let source = text as NSString
            for match in call.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                calls += 1
                let arguments = Self.arguments(in: source, from: match.range.upperBound)
                guard !arguments.contains("female:") else { continue }
                let key = "\(url.lastPathComponent)|\(arguments)"
                if !Self.spritesWithoutAnIndividual.contains(key) { offenders.append(key) }
            }
        }
        XCTAssertGreaterThan(calls, 20, "the scan found too few sprite calls; it is broken")
        XCTAssertTrue(offenders.isEmpty, """
            A sprite of an individual passes female: so its still and animated art show its gender; \
            list it in spritesWithoutAnIndividual only if it draws no individual: \(offenders.joined(separator: "\n"))
            """)
    }

    private static func arguments(in source: NSString, from start: Int) -> String {
        var depth = 1
        var index = start
        while depth > 0, index < source.length {
            switch source.character(at: index) {
            case 40: depth += 1
            case 41: depth -= 1
            default: break
            }
            index += 1
        }
        return source.substring(with: NSRange(location: start, length: index - 1 - start))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func testNoScreenReadsSpeciesDetailsWithoutTheIndividualsForm() throws {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("pokemonDetailsByID[") {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Screens read details through store.pokemonDetails(speciesID:form:gender:) so a form or gender with its own variety \
            shows its own types, stats and abilities: \(offenders.joined(separator: ", "))
            """)
    }
}
