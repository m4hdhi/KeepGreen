import SwiftUI

/// KeepGreen for iPhone: a remote control for KeepGreen on your Windows PC or Mac, over your own Wi-Fi.
/// iOS can't keep another app's status alive, so the work happens on the computer; this app watches
/// and steers it. No accounts, no cloud, no telemetry: the phone talks only to computers you pair.
@main
struct KeepGreenRemoteApp: App {
    @StateObject private var store = DesktopStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .tint(Palette.green)
        }
    }
}
