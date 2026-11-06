import KeepGreenKit
import SwiftUI

/// The paired computers, each with a live status dot. Also where pairing links from the Camera land.
struct HomeView: View {
    @EnvironmentObject private var store: DesktopStore
    @State private var path: [UUID] = []
    @State private var sheet: HomeSheet?

    private enum HomeSheet: Identifiable {
        case add
        case confirm(PairingLink)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .confirm(let link):
                return "pair-\(link.host)-\(link.port)-\(link.code)"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.desktops.isEmpty {
                    EmptyComputersView { sheet = .add }
                } else {
                    computerList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("KeepGreen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sheet = .add
                    } label: {
                        Label("Add computer", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ComputerDetailView(desktopID: id, store: store)
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                AddComputerView(store: store) { desktop in
                    showComputer(desktop)
                }
            case .confirm(let link):
                PairConfirmView(link: link, store: store) { desktop in
                    showComputer(desktop)
                }
            }
        }
        .onOpenURL { url in
            // keepgreen://pair?... from the QR code a Mac shows, scanned with the iPhone Camera.
            guard let link = PairingLink(url: url) else { return }
            sheet = .confirm(link)
        }
    }

    private var computerList: some View {
        List {
            Section {
                ForEach(store.desktops) { desktop in
                    NavigationLink(value: desktop.id) {
                        ComputerRow(desktop: desktop, snapshot: store.snapshots[desktop.id])
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.desktops[$0].id }
                    for id in ids {
                        store.remove(id: id)
                    }
                }
            } header: {
                Text("Your computers")
            } footer: {
                Text("Your iPhone talks to your computers directly over Wi-Fi. Pull down to refresh.")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refreshAll() }
        // Cancelled by SwiftUI when the list goes off screen, e.g. while a computer is open.
        .task { await store.keepRefreshing() }
    }

    private func showComputer(_ desktop: RemoteDesktop) {
        path = [desktop.id]
    }
}

/// One computer in the list: platform icon with a status dot, name, and the desktop's own headline.
private struct ComputerRow: View {
    let desktop: RemoteDesktop
    let snapshot: StatusSnapshot?

    private var isOffline: Bool {
        snapshot?.errorMessage != nil
    }

    private var dotColor: Color {
        guard !isOffline, let status = snapshot?.status else { return Palette.grey }
        return Palette.color(forState: status.state)
    }

    private var subtitle: String {
        if let snapshot = snapshot, snapshot.errorMessage != nil {
            return snapshot.needsPairing ? "Needs pairing again" : "Can't reach it right now"
        }
        return snapshot?.status?.headline ?? "Checking…"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: Format.platformSymbol(desktop.platform))
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                StatusDot(color: dotColor, hollow: isOffline || snapshot?.status == nil)
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(desktop.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// The little status light. Hollow while we don't know.
private struct StatusDot: View {
    let color: Color
    let hollow: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .frame(width: 18, height: 18)
            if hollow {
                Circle()
                    .strokeBorder(color, lineWidth: 2.5)
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: color)
    }
}

/// First run: what to do on the computer, and the way in for Windows (type the address and code).
private struct EmptyComputersView: View {
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                StatusOrb(color: Palette.green, symbol: "iphone.radiowaves.left.and.right", pulses: true, size: 72)
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    Text("Keep your computer green from here")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("See at a glance that your computer is staying green, flip KeepGreen on or off, or start a boost.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 16) {
                    StepRow(number: 1, text: "On your computer, open KeepGreen → Settings → Phone remote and turn it on.")
                    StepRow(number: 2, text: "On a Mac, scan the QR code with your iPhone Camera.")
                    StepRow(number: 3, text: "On Windows, tap Add computer and type the address and code shown.")
                }
                .keepGreenCard()

                Button(action: onAdd) {
                    Label("Add computer", systemImage: "plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Your iPhone and computer need to be on the same Wi-Fi.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number))
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Palette.green))
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
