import SwiftUI
import PUSHCore

// MARK: - Licence

struct LicenseSettingsView: View {
    @State private var license = LicenseModel.shared
    @State private var keyText = ""

    /// Polar's checkout for PUSH (sandbox until the store opens).
    private let buyURL = PolarConfig.current.checkoutURL
    private let addMacURL = PolarConfig.current.addMacCheckoutURL

    var body: some View {
        Form {
            if let stored = license.stored {
                Section {
                    LabeledContent("Status") {
                        Label("Activated on this Mac", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    LabeledContent("Key") {
                        Text(stored.activation.displayKey).font(.body.monospaced())
                    }
                    if let limit = stored.activation.activationLimit {
                        LabeledContent("Macs") { Text("Up to \(limit) with this key") }
                    }
                    LabeledContent("This Mac") { Text(MacModelLabel.current()) }
                } footer: {
                    Text("Moving to a new Mac? Remove this one first to free its place.")
                }
                Section {
                    Button("Remove This Mac") { Task { await license.removeThisMac() } }
                        .disabled(license.isWorking)
                }
            } else {
                Section {
                    TextField("Licence key", text: $keyText, prompt: Text("Paste the key from your receipt"))
                        .font(.body.monospaced())
                        .onSubmit { Task { await license.activate(key: keyText) } }
                    HStack {
                        Button("Activate") { Task { await license.activate(key: keyText) } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty || license.isWorking)
                        if license.isWorking { ProgressView().controlSize(.small) }
                        Spacer()
                        Link("Buy PUSH", destination: buyURL)
                        Link("Add a Mac ($10)", destination: addMacURL)
                    }
                } header: {
                    Text("Licence")
                } footer: {
                    Text("One key works on 3 Macs; a fourth needs its own $10 key. Activating sends the key and this Mac's model (\(MacModelLabel.current())) to Polar, which sells PUSH. Never your audio or anything you dictate.")
                }
            }

            if let message = license.message {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}
