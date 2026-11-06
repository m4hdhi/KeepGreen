import Combine
import Foundation
import KeepGreenKit

/// Everything the computer screen shows and does. Answers are also handed to the store,
/// so the list's status dots are current when you go back.
@MainActor
final class ComputerViewModel: ObservableObject {
    enum Action: Equatable {
        case toggle
        case boost(minutes: Int)
        case endOfWorkday
        case cancelBoost
    }

    @Published private(set) var status: RemoteStatus?
    @Published private(set) var errorMessage: String?
    @Published private(set) var needsPairing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var running: Action? = nil

    /// The master switch. Flipping it sends the change; answers from the computer move it without sending anything.
    @Published var switchIsOn: Bool {
        didSet {
            guard !isSyncingSwitch, switchIsOn != oldValue else { return }
            let wanted = switchIsOn
            Task { await self.setEnabled(wanted) }
        }
    }

    let desktopID: UUID
    private let store: DesktopStore
    private var isSyncingSwitch = false
    /// When the request behind the newest answer on screen was sent. Older answers that arrive late are dropped.
    private var shownRequestTime = Date.distantPast

    init(desktopID: UUID, store: DesktopStore) {
        self.desktopID = desktopID
        self.store = store
        let snapshot = store.snapshots[desktopID]
        _status = Published(initialValue: snapshot?.status)
        _errorMessage = Published(initialValue: snapshot?.errorMessage)
        _needsPairing = Published(initialValue: snapshot?.needsPairing ?? false)
        _lastUpdated = Published(initialValue: snapshot?.updatedAt)
        _switchIsOn = Published(initialValue: snapshot?.status?.isEnabled ?? false)
    }

    var canControl: Bool {
        status != nil && running == nil
    }

    // MARK: Refreshing

    /// Refreshes every 5 seconds until the calling task is cancelled. The screen runs this from
    /// `.task`, which SwiftUI cancels when the screen disappears.
    func keepRefreshing() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    func refresh() async {
        // A command is on its way; its own answer is fresher than anything a refresh could bring.
        guard running == nil, let desktop = store.desktop(withID: desktopID) else { return }
        let sentAt = Date()
        do {
            let status = try await RemoteClient(desktop: desktop).status()
            guard running == nil else { return }
            show(status, sentAt: sentAt)
        } catch is CancellationError {
            // Left the screen.
        } catch {
            guard running == nil else { return }
            showFailure(error, sentAt: sentAt)
        }
    }

    // MARK: Commands

    func boost(minutes: Int) async {
        await perform(.boost(minutes: minutes)) { try await $0.boost(minutes: minutes) }
    }

    func boostUntilEndOfWorkday() async {
        await perform(.endOfWorkday) { try await $0.boostUntilEndOfWorkday() }
    }

    func cancelBoost() async {
        await perform(.cancelBoost) { try await $0.cancelBoost() }
    }

    private func setEnabled(_ enabled: Bool) async {
        await perform(.toggle) { try await $0.setEnabled(enabled) }
    }

    private func perform(_ action: Action, _ work: (RemoteClient) async throws -> RemoteStatus) async {
        guard running == nil, let desktop = store.desktop(withID: desktopID) else {
            syncSwitch()
            return
        }
        running = action
        Haptics.tap()
        let sentAt = Date()

        do {
            let status = try await work(RemoteClient(desktop: desktop))
            running = nil
            show(status, sentAt: sentAt)
            Haptics.success()
        } catch is CancellationError {
            running = nil
            syncSwitch()
        } catch {
            running = nil
            showFailure(error, sentAt: sentAt)
            syncSwitch()
            Haptics.failure()
        }
    }

    // MARK: Showing answers

    private func show(_ status: RemoteStatus, sentAt: Date) {
        guard sentAt >= shownRequestTime else { return }
        shownRequestTime = sentAt
        self.status = status
        errorMessage = nil
        needsPairing = false
        lastUpdated = Date()
        syncSwitch()
        store.record(status, for: desktopID)
    }

    private func showFailure(_ error: Error, sentAt: Date) {
        guard sentAt >= shownRequestTime else { return }
        errorMessage = error.localizedDescription
        if let clientError = error as? RemoteClientError, case .unauthorized = clientError {
            needsPairing = true
        } else {
            needsPairing = false
        }
        store.recordFailure(error, for: desktopID)
    }

    /// Puts the switch back where the computer says it is, without sending anything.
    private func syncSwitch() {
        let actual = status?.isEnabled ?? false
        guard switchIsOn != actual else { return }
        isSyncingSwitch = true
        switchIsOn = actual
        isSyncingSwitch = false
    }
}
