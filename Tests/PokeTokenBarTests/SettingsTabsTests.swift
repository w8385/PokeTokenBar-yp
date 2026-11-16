import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class SettingsTabsTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "SettingsTabs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func uploader(status: Int, linked: Bool = true, server: String = "http://bot-host:8790") throws -> PartyUploader {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("settings-tabs-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: directory.appendingPathComponent("token")), defaults: try defaults(),
            appVersion: "test", exchange: { _ in (Data(), status) }, fetch: { _ in (Data(), 404) },
            partySource: { [PartyMember(pokemonID: 25, level: 10, shiny: false, ivs: nil)] })
        if linked { uploader.saveToken("synthetic-token") }
        uploader.serverURL = server
        return uploader
    }

    // MARK: Grouping

    func testEveryFormerSectionLivesInExactlyOneTab() {
        let former: Set<SettingsSection> = [.general, .difficulty, .menuBar, .trackedProviders, .floatingPet,
                                            .notifications, .update, .transfer, .advanced, .aboutSupport]
        let placed = SettingsTab.allCases.flatMap(\.sections)
        XCTAssertEqual(placed.count, Set(placed).count, "a section sits in two tabs")
        XCTAssertEqual(Set(placed), Set(SettingsSection.allCases), "a section sits in no tab")
        XCTAssertTrue(former.isSubset(of: Set(placed)))
        XCTAssertTrue(SettingsTab.allCases.allSatisfy { !$0.sections.isEmpty })
        XCTAssertTrue((4...6).contains(SettingsTab.allCases.count))
    }

    func testYPokeTabHoldsOnlyTheConnection() {
        XCTAssertEqual(SettingsTab.ypoke.sections, [.ypoke])
    }

    func testTabBarFitsThePopoverWidthForEveryLanguageAndSelectedTab() {
        for language in AppLanguage.allCases {
            for selected in SettingsTab.allCases {
                var selection = selected
                let picker = NSHostingView(rootView: SettingsTabPicker(
                    selection: Binding(get: { selection }, set: { selection = $0 }), l: L(language)))
                XCTAssertLessThanOrEqual(picker.fittingSize.width, PopoverMetrics.width - 32,
                                         "\(language) / \(selected): the settings tab bar needs more than the popover width")
            }
        }
    }

    // MARK: Persistence

    func testSelectedTabPersistsAcrossLaunchesAndSurvivesReset() throws {
        let defaults = try defaults()
        let first = PopoverNavigation(defaults: defaults)
        XCTAssertEqual(first.settingsTab, .general)
        first.settingsTab = .usage
        first.reset()
        XCTAssertEqual(first.settingsTab, .usage)
        XCTAssertEqual(PopoverNavigation(defaults: defaults).settingsTab, .usage)
    }

    func testUnknownStoredTabFallsBackToGeneral() throws {
        let defaults = try defaults()
        defaults.set("removed-tab", forKey: SettingsTab.defaultsKey)
        XCTAssertEqual(PopoverNavigation(defaults: defaults).settingsTab, .general)
    }

    // MARK: YPoke link

    func testBattleTabPointsToSettingsOnlyWhileUnlinkedOrRejected() async throws {
        XCTAssertTrue(BattleView.needsConnection(try uploader(status: 200, linked: false)))
        XCTAssertFalse(BattleView.needsConnection(try uploader(status: 200)))
        XCTAssertFalse(BattleView.needsConnection(nil))
        let rejected = try uploader(status: 401)
        await rejected.tick()
        XCTAssertTrue(rejected.tokenRejected)
        XCTAssertTrue(BattleView.needsConnection(rejected))
    }

    func testTheBattleLinkOpensSettingsOnTheYPokeTab() throws {
        let navigation = PopoverNavigation(defaults: try defaults())
        navigation.tab = .battle
        navigation.openYPokeSettings()
        XCTAssertTrue(navigation.showSettings)
        XCTAssertEqual(navigation.settingsTab, .ypoke)
    }

    func testSessionKeyNoticeStillOpensTheAdvancedTab() throws {
        let navigation = PopoverNavigation(defaults: try defaults())
        navigation.settingsTab = .ypoke
        navigation.openSessionKeySettings()
        XCTAssertEqual(navigation.settingsTab, .advanced)
    }

    func testBattleViewNoLongerOwnsTheTokenField() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let battle = try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/BattleView.swift"),
                                encoding: .utf8)
        XCTAssertFalse(battle.contains("SecureField"), "the upload token field belongs to Settings → YPoke")
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/SettingsView.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(settings.contains("SecureField"))
    }
}
