import AppKit
import KeepGreenKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var engine: PresenceEngine

    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var loginError: String? = nil

    init(engine: PresenceEngine) {
        self.engine = engine
    }

    private static let repositoryURL = URL(string: "https://github.com/m4hdhi/KeepGreen")!

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { setLaunchAtLogin($0) })) {
                    RowLabel(title: "Launch at login", subtitle: "Start KeepGreen when you log in to this Mac.")
                }
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("macOS needs your OK: turn KeepGreen on under System Settings → General → Login Items.")
                            .font(.caption)
                            .foregroundStyle(Color.statusAmber)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
                if let loginError = loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(Color.statusAmber)
                }

                Toggle(isOn: $engine.settings.notifications) {
                    RowLabel(title: "Notifications", subtitle: "A quick note when work hours start or end, or a boost runs out.")
                }

                HStack {
                    RowLabel(title: "Settings folder", subtitle: folderDisplay)
                    Spacer()
                    Button("Show in Finder") { showSettingsFolder() }
                }
            }

            Section("About") {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("KeepGreen")
                            .font(.title3.weight(.semibold))
                        Text(verbatim: "Version \(MacInfo.version)")
                            .foregroundStyle(.secondary)
                        Text("Made by Mahdhi Muzammil. Free and open source under the MIT license.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Use KeepGreen responsibly and within your organization's policies. It changes how idle your Mac looks, not how much you work.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("github.com/m4hdhi/KeepGreen", destination: GeneralSettingsView.repositoryURL)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    /// The folder as people write it, e.g. ~/Library/Application Support/KeepGreen.
    private var folderDisplay: String {
        let path = engine.store.folder.path
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func showSettingsFolder() {
        let folder = engine.store.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([engine.store.hasSavedSettings ? engine.store.settingsURL : folder])
    }
}
