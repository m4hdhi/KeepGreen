import KeepGreenKit
import SwiftUI

/// One computer: its status, the master switch, quick boosts and today's numbers.
struct ComputerDetailView: View {
    let desktopID: UUID

    @EnvironmentObject private var store: DesktopStore
    @StateObject private var model: ComputerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: DetailSheet?
    @State private var confirmRemove = false

    private enum DetailSheet: String, Identifiable {
        case edit
        case pairAgain
        var id: String { rawValue }
    }

    private struct BoostChoice: Identifiable {
        let minutes: Int
        let title: String
        var id: Int { minutes }
    }

    private static let boostChoices = [
        BoostChoice(minutes: 15, title: "15 min"),
        BoostChoice(minutes: 30, title: "30 min"),
        BoostChoice(minutes: 60, title: "1 hour"),
        BoostChoice(minutes: 120, title: "2 hours"),
    ]

    init(desktopID: UUID, store: DesktopStore) {
        self.desktopID = desktopID
        _model = StateObject(wrappedValue: ComputerViewModel(desktopID: desktopID, store: store))
    }

    private var desktop: RemoteDesktop? {
        store.desktop(withID: desktopID)
    }

    private var name: String {
        desktop?.name ?? "this computer"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                banner
                hero
                masterSwitch
                boosts
                today
                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(desktop?.name ?? "Computer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                moreMenu
            }
        }
        .refreshable { await model.refresh() }
        // SwiftUI cancels this task when the screen disappears, which ends the 5-second refresh loop.
        .task { await model.keepRefreshing() }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .confirmationDialog("Remove \(name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove computer", role: .destructive) {
                dismiss()
                store.remove(id: desktopID)
            }
        } message: {
            Text("This iPhone forgets it. KeepGreen keeps running on the computer, and you can pair again any time.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var banner: some View {
        if let message = model.errorMessage {
            if model.needsPairing {
                NoticeBanner(systemImage: "lock.trianglebadge.exclamationmark", message: message, actionTitle: "Pair again") {
                    sheet = .pairAgain
                }
            } else {
                NoticeBanner(systemImage: "wifi.exclamationmark", message: message, actionTitle: "Try again") {
                    Task { await model.refresh() }
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            StatusOrb(color: orbColor, symbol: orbSymbol, pulses: isStayingGreen)

            Text(headline)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let boost = boostText {
                Label(boost, systemImage: "bolt.fill")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .keepGreenCard(padding: 20)
        .accessibilityElement(children: .combine)
    }

    private var masterSwitch: some View {
        Toggle(isOn: $model.switchIsOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text("KeepGreen")
                    .font(.headline)
                Text(model.switchIsOn
                     ? "On. It steps in whenever this computer should look available."
                     : "Off. The computer can sleep and your status can go Away.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Palette.green)
        .disabled(!model.canControl)
        .keepGreenCard()
    }

    private var boosts: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Quick boost", systemImage: "bolt.fill")
                    .font(.headline)
                Text("Stay green for a while, even outside your schedule or with the switch off.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ComputerDetailView.boostChoices) { choice in
                    commandButton(choice.title, action: .boost(minutes: choice.minutes)) {
                        await model.boost(minutes: choice.minutes)
                    }
                }
            }

            commandButton("Until the end of my workday", action: .endOfWorkday) {
                await model.boostUntilEndOfWorkday()
            }

            if model.status?.isBoosted == true {
                commandButton("Cancel boost", action: .cancelBoost, role: .destructive) {
                    await model.cancelBoost()
                }
            }
        }
        .keepGreenCard()
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)
            HStack(spacing: 10) {
                StatTile(title: "Idle now", value: model.status.map { Format.duration(seconds: $0.idleSeconds) } ?? "–")
                StatTile(title: "Nudges", value: model.status.map { $0.nudgesToday.formatted() } ?? "–")
                StatTile(title: "Green", value: model.status.map { Format.duration(seconds: $0.greenSecondsToday) } ?? "–")
            }
        }
        .keepGreenCard()
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let updated = model.lastUpdated {
                Text("Last updated \(updated.formatted(date: .omitted, time: .standard))")
            }
            if let status = model.status {
                Text("KeepGreen \(status.version) on \(Format.platformName(status.platform)) · \(addressText)")
            } else {
                Text(addressText)
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                sheet = .edit
            } label: {
                Label("Rename or change address", systemImage: "pencil")
            }
            Button {
                sheet = .pairAgain
            } label: {
                Label("Pair again", systemImage: "link")
            }
            Divider()
            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Label("Remove computer", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: DetailSheet) -> some View {
        switch sheet {
        case .edit:
            if let desktop = desktop {
                EditComputerView(desktop: desktop) { edited in
                    store.update(edited)
                    Task { await model.refresh() }
                }
            }
        case .pairAgain:
            AddComputerView(
                store: store,
                title: "Pair again",
                host: desktop?.host ?? "",
                port: desktop?.port ?? RemoteDefaults.port
            ) { _ in
                Task { await model.refresh() }
            }
        }
    }

    private func commandButton(
        _ title: String,
        action: ComputerViewModel.Action,
        role: ButtonRole? = nil,
        perform: @escaping () async -> Void
    ) -> some View {
        Button(role: role) {
            Task { await perform() }
        } label: {
            ZStack {
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(model.running == action ? 0 : 1)
                if model.running == action {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!model.canControl)
    }

    // MARK: What to show

    private var isOffline: Bool {
        model.errorMessage != nil
    }

    private var isStayingGreen: Bool {
        !isOffline && model.status?.isActive == true
    }

    private var orbColor: Color {
        guard !isOffline, let status = model.status else { return Palette.grey }
        return Palette.color(forState: status.state)
    }

    private var orbSymbol: String? {
        if isOffline { return model.needsPairing ? "lock.fill" : "wifi.slash" }
        guard let status = model.status else { return nil }
        return status.isActive ? "checkmark" : "pause.fill"
    }

    private var headline: String {
        if isOffline { return model.needsPairing ? "Needs pairing again" : "Can't reach \(name)" }
        return model.status?.headline ?? "Checking…"
    }

    private var detail: String {
        if isOffline {
            if let updated = model.lastUpdated {
                return "Last heard from it at \(Format.time(updated))."
            }
            return ""
        }
        return model.status?.detail ?? "Asking \(name) how it's doing."
    }

    private var boostText: String? {
        guard !isOffline, let status = model.status, status.isBoosted else { return nil }
        guard let end = Format.date(fromISO8601: status.boostUntil) else { return "Boost on" }
        return "Boost on until \(Format.time(end))"
    }

    private var addressText: String {
        guard let desktop = desktop else { return "" }
        return "\(desktop.host):\(String(desktop.port))"
    }
}

/// One of the three numbers under "Today".
private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
    }
}
