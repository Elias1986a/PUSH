import SwiftUI
import AppKit
import PUSHCore

// MARK: - Licence

struct LicenseSettingsView: View {
    @State private var license = LicenseModel.shared
    @State private var confirmingRemove = false

    var body: some View {
        Form {
            if let stored = license.stored {
                if let offered = license.offeredKey {
                    Section {
                        Text("An activation link brought a different key (\(PolarLicenseClient.masked(offered))). Switch this Mac to it? Its place on the current key is freed.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Switch to This Key") { Task { await license.switchToOfferedKey() } }
                                .disabled(license.isWorking)
                            Button("Keep Current Key") { license.declineOfferedKey() }
                        }
                    }
                }
                Section {
                    LabeledContent("Status") {
                        if license.needsCheck() {
                            HStack {
                                Label("Needs a check with Polar", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Button("Check Now") { Task { await license.revalidate(force: true) } }
                                    .disabled(license.isWorking)
                            }
                        } else {
                            Label("Activated on this Mac", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
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
                        Button("Remove This Mac…") { confirmingRemove = true }
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
                    Text(.init(LicenseActivationControls.footnote))
                }
            }

            if license.stored != nil, let message = license.message {
                Section { LicenseMessage(text: message) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove PUSHTYPE from this Mac?", isPresented: $confirmingRemove) {
            Button("Remove This Mac", role: .destructive) { Task { await license.removeThisMac() } }
        } message: {
            Text("Talk and TYPE stop on this Mac, and its place goes back to your license for another Mac.")
        }
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

    /// Markdown (the agreement is a link): show it with `Text(.init(footnote))`.
    static let footnote = "One license works on 3 of your Macs; a fourth can be added for $12. Activating sends the key and this Mac's model (\(MacModelLabel.current())) to Polar, which sells PUSHTYPE. Never your audio or anything you type. By activating, you agree to the [License Agreement](https://pushtype.app/legal/eula.html)."

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
            Link("Add this Mac for $12 (same email as your license)", destination: PolarConfig.current.addMacCheckoutURL)
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
