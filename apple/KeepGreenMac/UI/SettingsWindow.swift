import AppKit
import KeepGreenKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule
    case behavior
    case remote
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .schedule: return "Schedule"
        case .behavior: return "Behavior"
        case .remote: return "Phone remote"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: return "calendar"
        case .behavior: return "cursorarrow.motionlines"
        case .remote: return "iphone"
        case .general: return "gearshape"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage? = .schedule
}

/// Owns the settings window. A plain AppKit window, so a menu bar app can open it on any macOS version
/// without the Settings scene's private selectors, and it never pops up by itself at launch.
@MainActor
final class SettingsWindowController {
    private let engine: PresenceEngine
    private let remote: RemoteServer
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(engine: PresenceEngine, remote: RemoteServer) {
        self.engine = engine
        self.remote = remote
    }

    func show(page: SettingsPage? = nil) {
        if let page = page {
            navigation.page = page
        }

        let window = self.window ?? makeWindow()
        self.window = window

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(engine: engine, remote: remote, navigation: navigation)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "KeepGreen Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        window.setFrameAutosaveName("KeepGreenSettings")
        return window
    }
}

struct SettingsRootView: View {
    @ObservedObject var engine: PresenceEngine
    @ObservedObject var remote: RemoteServer
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPage.allCases, selection: $navigation.page) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            Group {
                switch navigation.page ?? .schedule {
                case .schedule:
                    ScheduleSettingsView(engine: engine)
                case .behavior:
                    BehaviorSettingsView(engine: engine)
                case .remote:
                    RemoteSettingsView(engine: engine, remote: remote)
                case .general:
                    GeneralSettingsView(engine: engine)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
        .tint(.keepGreen)
    }
}
