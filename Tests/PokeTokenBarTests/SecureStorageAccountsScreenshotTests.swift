import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in captures of Settings → Advanced before and after two slot folders are detected, sample data.
///
///     PTB_SLOT_ACCOUNTS_SCREENSHOT_DIR=/tmp/shots swift test --filter SecureStorageAccountsScreenshotTests
@MainActor
final class SecureStorageAccountsScreenshotTests: XCTestCase {
    private struct Failing: ClaudeLimitsProviding {
        func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw LimitsError.keychainInteractionNotAllowed }
    }

    private struct NoCodex: CodexLimitsProviding {
        func fetch() async throws -> CodexRateLimitStatus? { nil }
    }

    private struct NoAntigravity: AntigravityLimitsProviding {
        func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
            throw LimitsError.keychainInteractionNotAllowed
        }
    }

    private struct NoStatuses: ProviderStatusProviding {
        func fetch() async -> [String: ProviderStatus] { [:] }
    }

    private struct NoSessionKey: SessionKeyManaging {
        func credential() -> SessionKeyCredential? { nil }
        func organizations(sessionKey: String) async throws -> [SessionKeyOrganization] { [] }
        func save(key: String, organizationID: String?) throws {}
        func clear() {}
    }

    func testCaptureAdvancedSettingsBeforeAndAfterSlotDetection() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_SLOT_ACCOUNTS_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_SLOT_ACCOUNTS_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("slot-accounts-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let slots = ["/Users/example/.claude-acct-personal-standby", "/Users/example/.claude-acct-team-standby"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }

        for language in [AppLanguage.ko, .en] {
            for (stage, detected) in [("before", [URL]()), ("after", slots)] {
                let defaults = UserDefaults(suiteName: "slot-accounts-shot-\(UUID())")!
                var state = CompanionState()
                state.language = language
                let file = scratch.appendingPathComponent("state-\(language.rawValue)-\(stage).json")
                try JSONEncoder().encode(state).write(to: file)
                let store = CompanionStore(fileURL: file, defaults: defaults)
                let usage = UsageStore(
                    providers: [], claudeLimitsProvider: Failing(),
                    additionalClaudeLimitsProvider: { _ in Failing() },
                    discoverClaudeConfigDirs: { detected },
                    readDefaultIdentity: { nil }, readLastPrompt: { _ in nil },
                    claudeUsageEntries: { _ in [] }, readPromptHistory: { _ in [:] },
                    codexLimitsProvider: NoCodex(), antigravityLimitsProvider: NoAntigravity(),
                    statusProvider: NoStatuses(), sessionKeys: NoSessionKey(),
                    accountSessionKeys: { _ in NoSessionKey() }, autoRefresh: false, defaults: defaults)
                await usage.refresh(scheduleEmptyRetry: false)
                XCTAssertEqual(usage.detectedClaudeConfigDirs.count, detected.count)
                let uploader = PartyUploader(
                    tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
                    appVersion: "shot", exchange: { _ in (Data(), 200) }, fetch: { _ in (Data(), 404) },
                    partySource: { [] })
                let size = NSSize(width: PopoverMetrics.width, height: 460)
                let host = OffscreenRender.host(
                    SettingsView(onClose: {}, onChooseRepresentative: {}, startExpanded: true, tab: .constant(.advanced))
                        .environment(usage).environment(store).environment(UpdateChecker()).environment(uploader)
                        .frame(width: size.width, height: size.height)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, .light)
                        .environment(\.locale, language.displayLocale),
                    size: size, appearance: .aqua)
                let window = OffscreenRender.windowHosting(host, appearance: .aqua)
                defer { window.close() }
                func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                let placeholder = store.l.additionalClaudeAccountsPlaceholder
                func accountsField() -> NSView? {
                    descendants(host).first { ($0 as? NSTextField)?.placeholderString == placeholder }
                }
                try await OffscreenRender.settle(host) { accountsField() != nil }
                let field = try XCTUnwrap(accountsField())
                let scroll = try XCTUnwrap(sequence(first: field, next: \.superview).compactMap { $0 as? NSScrollView }.last)
                let document = try XCTUnwrap(scroll.documentView)
                let frame = document.convert(field.bounds, from: field)
                let clip = scroll.contentView
                let bottom = document.isFlipped ? frame.maxY + 40 : frame.minY - 40
                let top = document.isFlipped ? bottom - clip.bounds.height : bottom
                clip.scroll(to: NSPoint(x: 0, y: max(0, min(top, document.bounds.height - clip.bounds.height))))
                scroll.reflectScrolledClipView(clip)
                try await OffscreenRender.settle(host)
                try OffscreenRender.writePNG(
                    of: host,
                    to: directory.appendingPathComponent("settings-advanced-accounts-\(stage)-\(language.rawValue).png"),
                    scale: 2)
            }
        }
    }
}
