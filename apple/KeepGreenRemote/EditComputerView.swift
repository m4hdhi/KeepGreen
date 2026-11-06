import KeepGreenKit
import SwiftUI

/// Rename a computer, or point the app at its new address. The pairing key stays the same.
struct EditComputerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var port: String
    private let original: RemoteDesktop
    private let onSave: (RemoteDesktop) -> Void

    init(desktop: RemoteDesktop, onSave: @escaping (RemoteDesktop) -> Void) {
        original = desktop
        self.onSave = onSave
        _name = State(initialValue: desktop.name)
        _address = State(initialValue: desktop.host)
        _port = State(initialValue: String(desktop.port))
    }

    /// The edited computer, or `nil` while something typed doesn't make sense.
    private var edited: RemoteDesktop? {
        let parts = AddressInput.split(address)
        guard !parts.host.isEmpty, let typedPort = AddressInput.port(port) else { return nil }
        var desktop = original
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        desktop.name = trimmedName.isEmpty ? original.name : trimmedName
        desktop.host = parts.host
        desktop.port = (parts.port != nil && typedPort == RemoteDefaults.port) ? (parts.port ?? typedPort) : typedPort
        return desktop
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Only changes the name on this iPhone.")
                }

                Section {
                    TextField("192.168.1.20", text: $address)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Text("Port")
                            .foregroundColor(.secondary)
                        TextField(String(RemoteDefaults.port), text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Address")
                } footer: {
                    Text("If your computer got a new address on the network, type it here. No need to pair again.")
                }
            }
            .navigationTitle("Edit computer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let desktop = edited {
                            onSave(desktop)
                            dismiss()
                        }
                    }
                    .disabled(edited == nil)
                }
            }
        }
    }
}
