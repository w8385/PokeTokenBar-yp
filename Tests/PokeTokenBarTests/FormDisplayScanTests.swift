import XCTest

final class FormDisplayScanTests: XCTestCase {
    func testNoScreenReadsSpeciesDetailsWithoutTheIndividualsForm() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("pokemonDetailsByID[") {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Screens read details through store.pokemonDetails(speciesID:form:) so a form with its own variety \
            shows its own types, stats and abilities: \(offenders.joined(separator: ", "))
            """)
    }
}
