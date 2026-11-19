import Foundation
@testable import PokeTokenBar

/// No incidents. A test `UsageStore` passes this or its own fake: the default fetches the live status pages.
struct NoProviderStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}

private enum OfflineLimitsError: Error { case unavailable }

private struct OfflineClaudeLimits: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw OfflineLimitsError.unavailable }
}

private struct OfflineCodexLimits: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}

struct OfflineAntigravityLimits: AntigravityLimitsProviding {
    var hasTokenFile: Bool { false }
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw OfflineLimitsError.unavailable
    }
}

struct OfflineCursorLimits: CursorLimitsProviding {
    func fetch() async throws -> CursorRateLimitStatus? { nil }
}

struct OfflineOpenCodeGoLimits: OpenCodeGoLimitsProviding {
    func fetch() async throws -> OpenCodeGoRateLimitStatus? { nil }
}

struct OfflineGrokLimits: GrokLimitsProviding {
    func fetch() async throws -> GrokCreditStatus? { nil }
}

struct OfflineSessionKeys: SessionKeyManaging {
    func credential() -> SessionKeyCredential? { nil }
    func organizations(sessionKey: String) async throws -> [SessionKeyOrganization] { [] }
    func save(key: String, organizationID: String?) throws {}
    func clear() {}
}

extension UsageStore {
    /// A store that reads nothing from the machine it runs on: no Claude or Codex folders, credentials, Keychain,
    /// limits or status pages. Every limit reads as unavailable and every provider as operational.
    @MainActor
    static func offline(providers: [any UsageProvider], defaults: UserDefaults, pinnedNow: Date? = nil) -> UsageStore {
        UsageStore(providers: providers,
                   claudeLimitsProvider: OfflineClaudeLimits(),
                   additionalClaudeLimitsProvider: { _ in OfflineClaudeLimits() },
                   discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil }, readLastPrompt: { _ in nil },
                   claudeUsageEntries: { _ in [] }, readPromptHistory: { _ in [:] },
                   codexLimitsProvider: OfflineCodexLimits(), antigravityLimitsProvider: OfflineAntigravityLimits(),
                   cursorLimitsProvider: OfflineCursorLimits(), openCodeGoLimitsProvider: OfflineOpenCodeGoLimits(),
                   grokLimitsProvider: OfflineGrokLimits(), statusProvider: NoProviderStatus(),
                   sessionKeys: OfflineSessionKeys(), accountSessionKeys: { _ in OfflineSessionKeys() },
                   autoRefresh: false, defaults: defaults, displaysAsleep: { false }, pinnedNow: pinnedNow)
    }
}
