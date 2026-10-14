import SwiftUI
import AppKit
import PUSHCore

// MARK: - Licence

struct LicenseSettingsView: View {
    @State private var license = LicenseModel.shared

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
                    Text("Your other Macs signed in to the same Apple Account activate on their own. Moving to a new Mac? Remove this one first to free its place.")
                }
                Section {
                    HStack {
                        Button("Remove This Mac") { Task { await license.removeThisMac() } }
                            .disabled(license.isWorking)
                        Spacer()
                        Link("See all your Macs", destination: PolarConfig.current.portalURL)
                    }
                }
            } else {
                Section {
                    LicenseActivationControls()
                } header: {
                    Text("License")
                } footer: {
                    Text(LicenseActivationControls.footnote)
                }
            }

            if license.stored != nil, let message = license.message {
                Section { LicenseMessage(text: message) }
            }
        }
        .formStyle(.grouped)
    }
}

/// Everything for a Mac without a licence, shared by Settings and the welcome
/// window: the one-click ways first (a key from iCloud, a key just copied),
/// typing the key as the backup, and the way out when the key is on all its
/// Macs.
struct LicenseActivationControls: View {
    @State private var license = LicenseModel.shared
    @State private var keyText = ""
    @State private var iCloudKey: String?
    @State private var copiedKey: String?

    static let footnote = "One license works on 3 of your Macs; a fourth can be added for $12. Activating sends the key and this Mac's model (\(MacModelLabel.current())) to Polar, which sells PUSHTYPE. Never your audio or anything you type."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let key = iCloudKey {
                Button {
                    Task { await license.activate(key: key) }
                } label: {
                    Label("Use the license from your other Mac", systemImage: "icloud")
                }
                .buttonStyle(.borderedProminent)
                .disabled(license.isWorking)
            } else if let key = copiedKey {
                Button {
                    Task { await license.activate(key: key) }
                } label: {
                    Label("Activate with the key you copied (\(PolarLicenseClient.masked(key)))", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .disabled(license.isWorking)
            }

            HStack {
                TextField("License key", text: $keyText, prompt: Text("Or paste the key from Polar's email"))
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await license.activate(key: keyText) } }
                Button("Activate") { Task { await license.activate(key: keyText) } }
                    .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty || license.isWorking)
                if license.isWorking { ProgressView().controlSize(.small) }
            }

            if let message = license.message {
                LicenseMessage(text: message)
            }
            if license.refusedForLimit {
                LicenseLimitChoices()
            }

            HStack {
                Link("Buy PUSHTYPE", destination: PolarConfig.current.checkoutURL)
                Spacer()
                Link("Lost your key?", destination: PolarConfig.current.portalURL)
            }
            .font(.callout)
        }
        .onAppear(perform: refresh)
        // Copying the key from the email happens in another app: look again
        // when PUSHTYPE comes back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        iCloudKey = license.iCloudKey
        copiedKey = license.clipboardKey
    }
}

/// A fourth Mac: the licence is on 3 already. Three ways forward, cheapest
/// first; the portal shows which Macs hold the places, to remove one.
private struct LicenseLimitChoices: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link("Add this Mac for $12", destination: PolarConfig.current.addMacCheckoutURL)
            Link("Buy another license ($35)", destination: PolarConfig.current.checkoutURL)
            Link("Free a place: remove a Mac you no longer use", destination: PolarConfig.current.portalURL)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }
}

private struct LicenseMessage: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
