import Combine
import Foundation
import KeepGreenKit

/// The last thing we heard from one computer.
struct StatusSnapshot {
    var status: RemoteStatus?
    /// Set when the last try failed. `status` then still holds the last good answer, if any.
    var errorMessage: String?
    /// The computer turned this phone away (new key or clocks apart), so it needs pairing again.
    var needsPairing = false
    var updatedAt: Date?
}

/// The paired computers, saved on this iPhone, plus the latest status of each.
///
/// Paired computers are kept as JSON in UserDefaults. Their keys are secrets: in a later version
/// they belong in the Keychain. For v1 they stay in the app's own sandboxed defaults, which are
/// covered by iOS data protection but are included in unencrypted device backups.
@MainActor
final class DesktopStore: ObservableObject {
    @Published private(set) var desktops: [RemoteDesktop] = []
    @Published private(set) var snapshots: [UUID: StatusSnapshot] = [:]

    private let defaults: UserDefaults
    private static let storageKey = "KeepGreen.pairedDesktops.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: DesktopStore.storageKey),
           let saved = try? JSONDecoder().decode([RemoteDesktop].self, from: data) {
            desktops = saved
        }
    }

    func desktop(withID id: UUID) -> RemoteDesktop? {
        desktops.first { $0.id == id }
    }

    // MARK: Editing the list

    /// Saves a freshly paired computer. If one at the same address is already saved, it is replaced
    /// in place (same id and position), so pairing again just refreshes the key.
    @discardableResult
    func savePaired(_ desktop: RemoteDesktop) -> RemoteDesktop {
        if let index = desktops.firstIndex(where: { DesktopStore.sameAddress($0, desktop) }) {
            var replacement = desktop
            replacement.id = desktops[index].id
            desktops[index] = replacement
            snapshots[replacement.id] = nil
            persist()
            return replacement
        }
        desktops.append(desktop)
        persist()
        return desktop
    }

    /// Saves a new name or address. The key stays the same.
    func update(_ desktop: RemoteDesktop) {
        guard let index = desktops.firstIndex(where: { $0.id == desktop.id }) else { return }
        let addressChanged = !DesktopStore.sameAddress(desktops[index], desktop)
        desktops[index] = desktop
        if addressChanged {
            snapshots[desktop.id] = nil
        }
        persist()
    }

    func remove(id: UUID) {
        desktops.removeAll { $0.id == id }
        snapshots[id] = nil
        persist()
    }

    // MARK: Status

    func record(_ status: RemoteStatus, for id: UUID) {
        guard desktop(withID: id) != nil else { return }
        snapshots[id] = StatusSnapshot(status: status, errorMessage: nil, needsPairing: false, updatedAt: Date())
    }

    func recordFailure(_ error: Error, for id: UUID) {
        guard desktop(withID: id) != nil else { return }
        var snapshot = snapshots[id] ?? StatusSnapshot()
        snapshot.errorMessage = error.localizedDescription
        if let clientError = error as? RemoteClientError, case .unauthorized = clientError {
            snapshot.needsPairing = true
        } else {
            snapshot.needsPairing = false
        }
        snapshots[id] = snapshot
    }

    /// Asks one computer for its status and remembers the answer.
    func refresh(_ desktop: RemoteDesktop) async {
        do {
            let status = try await RemoteClient(desktop: desktop).status()
            record(status, for: desktop.id)
        } catch is CancellationError {
            // The screen went away; nothing to show.
        } catch {
            recordFailure(error, for: desktop.id)
        }
    }

    /// Asks every computer at once and returns when all have answered or timed out.
    func refreshAll() async {
        let tasks = desktops.map { desktop in
            Task { await self.refresh(desktop) }
        }
        for task in tasks {
            await task.value
        }
    }

    /// Refreshes every few seconds until the calling task is cancelled (the list goes off screen).
    func keepRefreshing(everySeconds seconds: UInt64 = 10) async {
        while !Task.isCancelled {
            await refreshAll()
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
        }
    }

    // MARK: Private

    private static func sameAddress(_ a: RemoteDesktop, _ b: RemoteDesktop) -> Bool {
        a.port == b.port && a.host.caseInsensitiveCompare(b.host) == .orderedSame
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(desktops) else { return }
        defaults.set(data, forKey: DesktopStore.storageKey)
    }
}
