import AppKit
import KeepGreenKit
import SwiftUI

@main
@MainActor
struct KeepGreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var icon: MenuBarIcon

    init() {
        _icon = ObservedObject(wrappedValue: AppModel.shared.engine.icon)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: AppModel.shared.engine) { page in
                AppModel.shared.showSettings(page: page)
            }
        } label: {
            Image(systemName: icon.symbol)
                .accessibilityLabel("KeepGreen: \(icon.label)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}

/// Wires the engine, the phone remote, notifications and the settings window together.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let engine: PresenceEngine
    let remote = RemoteServer()

    private let notifier = Notifier()
    private let isFirstLaunch: Bool
    private lazy var settingsWindow = SettingsWindowController(engine: engine, remote: remote)

    private init() {
        let store = SettingsStore()
        isFirstLaunch = !store.hasSavedSettings
        engine = PresenceEngine(settings: store.loadSettings(today: LocalDate(Date())), store: store)
        remote.engine = engine

        engine.onTransition = { [weak self] previous, current in
            self?.presenceChanged(from: previous, to: current)
        }
        engine.onSettingsChange = { [weak self] settings in
            self?.remote.update(enabled: settings.remoteEnabled, key: settings.remoteKey)
        }
    }

    func start() {
        // An older file may have the remote on without a valid key (normalize drops broken keys).
        if engine.settings.remoteEnabled && engine.settings.remoteKey == nil {
            engine.setRemoteEnabled(true)
        }

        engine.start()
        remote.update(enabled: engine.settings.remoteEnabled, key: engine.settings.remoteKey)

        if isFirstLaunch {
            // Menu bar apps are easy to miss; show where everything lives once.
            showSettings(page: .schedule)
        }
    }

    func shutdown() {
        remote.update(enabled: false, key: nil)
        engine.stop()
    }

    func showSettings(page: SettingsPage? = nil) {
        settingsWindow.show(page: page)
    }

    private func presenceChanged(from previous: PresenceDecision, to current: PresenceDecision) {
        guard engine.settings.notifications else { return }
        notifier.presenceChanged(from: previous, to: current, detail: engine.detail)
    }
}
