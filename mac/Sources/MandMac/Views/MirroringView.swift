import AppKit
import MandMacKit
import SwiftUI

struct MirroringView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card {
                    HStack(spacing: 16) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.title3.weight(.semibold))
                            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        primaryButton
                    }
                    if !model.mirroringOutput.isEmpty, case .failed = model.mirroringState {
                        Text(model.mirroringOutput.suffix(4).joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                ControlCard()
                SetupCard()
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .onAppear { model.refreshMirroring() }
    }

    private var title: String {
        switch model.mirroringState {
        case .notInstalled: "Set up screen mirroring"
        case .ready: "Show your phone’s screen on this Mac"
        case .running: "Mirroring is on"
        case .failed: "Mirroring stopped"
        }
    }

    private var subtitle: String {
        switch model.mirroringState {
        case .notInstalled: "M’AND uses scrcpy, a free open-source tool, to mirror your phone. Install it once (steps below)."
        case .ready: "Connect your phone with a USB cable, then click Start. The phone screen opens in its own window."
        case .running: "Close the mirroring window or click Stop to end."
        case .failed(let reason): reason
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch model.mirroringState {
        case .ready, .failed: Button("Start") { model.startMirroring() }.buttonStyle(.borderedProminent).controlSize(.large)
        case .running: Button("Stop") { model.stopMirroring() }.controlSize(.large)
        case .notInstalled: Button("Check Again") { model.refreshMirroring() }
        }
    }
}

private struct ControlCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Card(title: "Control from the Mac", subtitle: nil) {
            Toggle("Let this Mac’s mouse and keyboard control the phone", isOn: $settings.mirroringAllowsControl)
            Text("Off by default: mirroring is view-only. When on, anyone using this Mac can tap and type on your phone while mirroring runs. Applies the next time you start.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SetupCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(title: "One-time setup", subtitle: nil) {
            VStack(alignment: .leading, spacing: 8) {
                Tip("Download scrcpy for macOS (the “macos-aarch64” file) and unzip it into your Downloads or Applications folder.")
                Tip("The first time, macOS may block it: open System Settings → Privacy & Security and click “Open Anyway”.")
                Tip("On the phone: Settings → About phone → tap Build number 7 times, then Developer options → turn on USB debugging.")
                Tip("Connect the phone by USB and tap “Allow” when it asks about USB debugging.")
                HStack {
                    Button("Download scrcpy") { NSWorkspace.shared.open(ScrcpyManager.downloadPage) }
                    Button("Choose scrcpy…") { model.chooseScrcpy() }
                }
                .padding(.top, 4)
                if case .ready(let path) = model.mirroringState {
                    Text("Using \(path)").font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                }
            }
        }
    }
}
