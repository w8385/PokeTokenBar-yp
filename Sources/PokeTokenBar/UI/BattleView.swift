import SwiftUI

/// Battle tab: the YPoke bot connection and the battle entry.
@MainActor
struct BattleView: View {
    let store: CompanionStore
    let navigation: PopoverNavigation
    @Environment(PartyUploader.self) private var uploader: PartyUploader?
    @Environment(BattleEntryStore.self) private var entry: BattleEntryStore?

    @State private var tokenInput = ""
    @State private var tokenInvalid = false
    private let initialPickerQuery: String

    private var l: L { store.l }

    init(store: CompanionStore, navigation: PopoverNavigation, initialPickerQuery: String = "") {
        self.store = store
        self.navigation = navigation
        self.initialPickerQuery = initialPickerQuery
    }

    var body: some View {
        if navigation.showingBattlePicker, let entry, let uploader {
            BattleFighterPicker(
                store: store,
                current: BattleEntry.fighter(state: store.state, slot: entry.slot)?.id,
                initialQuery: initialPickerQuery,
                onPick: { id in
                    entry.choose(id)
                    navigation.showingBattlePicker = false
                    Task { await uploader.tick() }
                },
                onBack: { navigation.showingBattlePicker = false })
            .frame(height: 520)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let uploader {
                        connectionSection(uploader)
                        if uploader.hasToken, uploader.hasServer, let entry {
                            section(nil) {
                                BattleEntrySection(entry: entry, uploader: uploader) {
                                    navigation.showingBattlePicker = true
                                }
                            }
                        }
                        if uploader.hasToken, uploader.hasServer {
                            BattleInfoSections(info: uploader.battleInfo, l: l)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .reservesScrollerLane()
            }
            .frame(height: 520)
        }
    }

    private func connectionSection(_ uploader: PartyUploader) -> some View {
        @Bindable var uploader = uploader
        return section(l.partyUploadSectionTitle) {
            row {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(l.partyUploadTokenLabel)
                        if !uploader.hasToken {
                            Text(l.ypokeNotLinked).font(.caption2).foregroundStyle(.secondary)
                        } else if uploader.tokenRejected {
                            Text(l.partyUploadTokenRejected).font(.caption2).foregroundStyle(.orange)
                        } else if uploader.lastAttemptFailed {
                            Text(l.ypokeUploadFailed).font(.caption2).foregroundStyle(.orange)
                        } else if uploader.lastSuccessAt != nil {
                            Text(l.partyUploadConnected).font(.caption2).foregroundStyle(.green)
                        } else {
                            Text(l.partyUploadTokenSaved).font(.caption2).foregroundStyle(.green)
                        }
                    }
                    if uploader.hasToken {
                        Text(uploader.hasServer ? l.partyUploadHint : l.partyUploadLinkHint)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            if !uploader.hasToken {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(l.ypokeLinkSteps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)").fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            row {
                SecureField(uploader.hasToken ? "••••••••" : l.partyUploadTokenLabel, text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitToken(uploader) }
                Button(l.save) { submitToken(uploader) }
                    .disabled(tokenInput.isEmpty)
                if uploader.hasToken {
                    Button(l.delete) {
                        tokenInput = ""
                        tokenInvalid = false
                        uploader.clearToken()
                    }
                }
            }
            if tokenInvalid {
                Text(l.partyUploadTokenInvalid)
                    .font(.caption2).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            } else if uploader.hasToken {
                VStack(alignment: .leading, spacing: 2) {
                    if uploader.lastAttemptFailed, !uploader.tokenRejected {
                        Text(l.ypokeUploadFailedHint).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let sent = uploader.lastSuccessAt {
                        Text("\(l.partyUploadLastSent): \(sent, format: .dateTime.month().day().hour().minute())")
                    } else if uploader.hasServer, !uploader.tokenRejected, !uploader.lastAttemptFailed {
                        Text(l.battleEntryNotSent).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(l.partyUploadStorageNote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
            Divider()
            row {
                Text(l.partyUploadServerLabel)
                Spacer()
                TextField("http://bot-host:8790", text: $uploader.serverURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
        }
    }

    private func submitToken(_ uploader: PartyUploader) {
        tokenInvalid = !uploader.saveToken(tokenInput)
        if !tokenInvalid {
            tokenInput = ""
            Task { await uploader.tick() }
        }
    }

    private func section<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    .textCase(.uppercase).padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 38)
    }
}
