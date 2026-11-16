import XCTest
@testable import PokeTokenBar

/// A fixture that answers for species X with species Y's types and stats proves nothing about X, and a
/// screenshot of it shows wrong facts (Onix rendered as a Normal-type Lv41). Species facts come from
/// `SpeciesFacts`; this scanner rejects every other place that builds them.
final class SpeciesFactsGuardTests: XCTestCase {
    /// Pieces, so this file does not match its own scan.
    private static let constructors = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_])(" + "PokemonDetails" + "|" + "SpeciesIndexEntry" + ")\\(")

    static func handBuiltConstructors(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            var code = String(line)
            if let comment = code.range(of: "//") { code = String(code[..<comment.lowerBound]) }
            let range = NSRange(code.startIndex..., in: code)
            return constructors.firstMatch(in: code, range: range).map { _ in line.trimmingCharacters(in: .whitespaces) }
        }
    }

    func testNoTestBuildsSpeciesFactsOutsideTheSharedSource() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard url.lastPathComponent != "SpeciesFacts.swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            offenders += Self.handBuiltConstructors(in: source).map { "\(url.lastPathComponent): \($0)" }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Tests must not hand-build species facts. Use SpeciesFacts.details(_:) / indexEntry(_:) for a real \
            species (add the id to scripts/generate-species-facts.py), or SpeciesFacts.counterfactual(because:…) \
            when the test needs a value no species has:
            \(offenders.joined(separator: "\n"))
            """)
    }

    func testTheScannerSeesAHandBuiltFactAndIgnoresLookalikes() {
        let built = "let d = Pokemon" + "Details(speciesID: 95, name: \"x\")"
        let entry = "    Species" + "IndexEntry(id: 1, names: [:])"
        XCTAssertEqual(Self.handBuiltConstructors(in: built + "\n" + entry).count, 2)
        for harmless in ["await store.loadPokemonDetails(speciesID: 95)",
                         "func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {",
                         "struct PokemonDetailsPlaceholder: View {",
                         "// " + built,
                         "let d = try SpeciesFacts.details(95)  // not " + built] {
            XCTAssertEqual(Self.handBuiltConstructors(in: harmless), [], harmless)
        }
    }

    func testAnIdOutsideTheTableFailsLoudlyInsteadOfFallingBack() throws {
        try XCTExpectFailure("an unknown species must record a failure, not return made-up details") {
            XCTAssertThrowsError(try SpeciesFacts.details(999_999))
        }
        try XCTExpectFailure("the index entry path fails the same way") {
            XCTAssertThrowsError(try SpeciesFacts.indexEntry(999_999))
        }
    }

    /// Facts typed from the games, not read back from the table, so a bad regeneration cannot agree with itself.
    func testTheTableMatchesWhatTheGamesSay() throws {
        let onix = try SpeciesFacts.details(95)
        XCTAssertEqual(onix.types, ["rock", "ground"])
        XCTAssertEqual(onix.baseStats["defense"], 160)
        XCTAssertEqual(onix.baseStatTotal, 385)
        let charizard = try SpeciesFacts.details(6)
        XCTAssertEqual(charizard.types, ["fire", "flying"])
        XCTAssertEqual(charizard.genderRate, 1)
        XCTAssertEqual(try SpeciesFacts.details(81).genderRate, -1, "Magnemite is genderless")
        XCTAssertEqual(try SpeciesFacts.details(33).genderRate, 0, "Nidorino is always male")
        XCTAssertEqual(try SpeciesFacts.details(292).baseStats["hp"], 1)
        let pikachu = try SpeciesFacts.indexEntry(25)
        XCTAssertEqual(pikachu.names["ko"], "피카츄")
        XCTAssertEqual(pikachu.evolvesFromID, 172)
        XCTAssertTrue(try SpeciesFacts.indexEntry(150).isLegendary)
    }

    func testEveryRowIsWellFormed() {
        XCTAssertEqual(SpeciesFacts.byID.count, SpeciesFacts.table.count, "duplicate species id")
        for fact in SpeciesFacts.table {
            XCTAssertEqual(fact.stats.count, PokemonStatCalculator.order.count, "#\(fact.id) stats")
            XCTAssertFalse(fact.stats.contains { $0 <= 0 }, "#\(fact.id) stats")
            XCTAssertTrue((1...2).contains(fact.types.count), "#\(fact.id) types")
            XCTAssertFalse(fact.en.isEmpty || fact.ko.isEmpty || fact.slug.isEmpty, "#\(fact.id) names")
            XCTAssertTrue((-1...8).contains(fact.genderRate), "#\(fact.id) gender rate")
        }
        XCTAssertEqual((1...151).filter { SpeciesFacts.byID[$0] == nil }, [], "Gen I is complete")
    }
}
