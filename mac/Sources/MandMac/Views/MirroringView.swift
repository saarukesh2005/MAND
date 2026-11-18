import MandCore
import AppKit
import MandMacKit
import SwiftUI

/// Screen mirroring: built in over Wi-Fi first (nothing to install), USB/scrcpy as an advanced option.
struct MirroringView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WifiMirroringCard()
                UsbMirroringSection()
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}

/// Built-in mirroring: one button, Android asks the person to confirm, the picture appears here.
struct WifiMirroringCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(title: "See your phone’s screen", subtitle: "Over Wi-Fi. Nothing to install and no cable. Your phone always asks first.") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                switch model.screenState {
                case .idle, .ended:
                    if case .ended(let message) = model.screenState { NoticeLine(text: message) }
                    Button { model.startPhoneScreen() } label: {
                        Label("Show Phone Screen", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.pill)
                    .disabled(!model.phoneSupports(Feature.screen))
                    if !model.isConnected {
                        Text("Connect your phone first.").foregroundStyle(.secondary)
                    } else if !model.phoneSupports(Feature.screen) {
                        Text("Update M’AND on your phone to use this.").foregroundStyle(.secondary)
                    }
                case .asking(let phone):
                    NoticeLine(text: "Look at \(phone): tap the M’AND notification, then “Start now”.", symbol: "hand.point.up.left")
                    Button("Cancel") { model.stopPhoneScreen() }
                case .showing(let phone, let width, let height, let hasPicture):
                    HStack {
                        Text(hasPicture ? "Showing \(phone)" : "Waiting for the first picture…").font(.headline)
                        Spacer()
                        Button { model.stopPhoneScreen() } label: { Label("Stop", systemImage: "stop.fill") }
                            .controlSize(.large)
                    }
                    let canControl = model.selected?.canControl == true
                    if let mirror = model.screenMirror {
                        ScreenLayerView(mirror: mirror)
                            .overlay { if canControl { ControlSurface() } }
                            .aspectRatio(CGFloat(width) / CGFloat(max(height, 1)), contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 640)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                            .accessibilityLabel("Live picture of \(phone)’s screen")
                    }
                    if canControl {
                        HStack(spacing: Theme.Space.s) {
                            Button { model.pressPhoneKey(.back) } label: { Label("Back", systemImage: "chevron.backward") }
                            Button { model.pressPhoneKey(.home) } label: { Label("Home", systemImage: "circle") }
                            Button { model.pressPhoneKey(.recents) } label: { Label("Recent Apps", systemImage: "square.on.square") }
                        }
                        .controlSize(.large)
                        Text("Click to tap. Drag to swipe or scroll.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("View only. To tap and swipe from this Mac, turn on “M’AND Tap to Send and control” in your phone’s Accessibility settings, then share again.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Hosts the mirror's AVSampleBufferDisplayLayer.
struct ScreenLayerView: NSViewRepresentable {
    let mirror: ScreenMirror

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.backgroundColor = .black
        mirror.layer.frame = view.bounds
        mirror.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(mirror.layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        mirror.layer.frame = view.bounds
    }
}

/// The original USB mirroring with scrcpy (needs a cable and USB debugging; allows control).
struct UsbMirroringSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DisclosureGroup("Advanced: mirror over USB with control (needs scrcpy)") {
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
            .padding(.top, 12)
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
        case .ready, .failed: Button("Start") { model.startMirroring() }.buttonStyle(.pill)
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
                Tip("Download scrcpy for macOS (the “macos-aarch64” file) and unzip it into your Applications folder — or anywhere, then click “Choose scrcpy…”.")
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

/// Turns clicks and drags on the mirrored picture into taps and swipes on the phone.
struct ControlSurface: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { drag in
                            let size = geometry.size
                            guard size.width > 0, size.height > 0 else { return }
                            let start = drag.startLocation, end = drag.location
                            let moved = hypot(end.x - start.x, end.y - start.y)
                            if moved < 6 {
                                model.tapPhone(atX: start.x / size.width, y: start.y / size.height)
                            } else {
                                let seconds = max(0.1, min(1.0, Double(moved / max(size.height, 1)) * 0.8))
                                model.swipePhone(fromX: start.x / size.width, y1: start.y / size.height,
                                                 toX: end.x / size.width, y2: end.y / size.height, seconds: seconds)
                            }
                        }
                )
                .accessibilityHidden(true) // VoiceOver users use the Back / Home / Recent Apps buttons
        }
    }
}
