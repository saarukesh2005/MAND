import AppKit
import MandMacKit
import SwiftUI

/// A black pill that drops out of the notch during Tap to Send: "Keep holding…", "Sent", or one simple tip.
/// It floats over everything, never takes focus, and is announced to VoiceOver.
@MainActor
final class NotchHUD {
    static let shared = NotchHUD()
    private var panel: NSPanel?
    private let state = NotchHUDState()
    private var hideWork: DispatchWorkItem?

    func show(_ phase: AppModel.TapPhase) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        state.phase = phase
        state.visible = true
        panel.orderFrontRegardless()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: phase.spoken, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        hideWork?.cancel()
        let delay: TimeInterval = if case .holding = phase { 6 } else { 2.6 }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hide() {
        state.visible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if self?.state.visible == false { self?.panel?.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 110),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: NotchPill(state: state))
        return panel
    }

    /// Centred under the notch on the built-in display (falls back to the main screen).
    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.frame else { return }
        let size = panel.frame.size
        let top = frame.maxY - (screen?.safeAreaInsets.top ?? 0)
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: top - size.height - 4))
    }
}

@MainActor
@Observable
final class NotchHUDState {
    var phase: AppModel.TapPhase = .holding
    var visible = false
}

private struct NotchPill: View {
    let state: NotchHUDState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if state.visible {
                HStack(spacing: 12) {
                    icon
                    Text(state.phase.text)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(
                    Capsule().fill(LinearGradient(colors: [Color(white: 0.16), .black], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                )
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .scale(scale: 0.6, anchor: .top)).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(width: 420, height: 110)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.72), value: state.visible)
        .animation(.easeInOut(duration: 0.2), value: state.phase)
    }

    @ViewBuilder private var icon: some View {
        switch state.phase {
        case .holding:
            ProgressView().controlSize(.small).tint(.white)
        case .sent:
            Image(systemName: "checkmark.circle.fill").font(.title2)
                .foregroundStyle(ChromeStyle.shine)
                .symbolEffect(.bounce, value: state.visible)
        case .failed:
            Image(systemName: "hand.point.up.left.fill").font(.title3).foregroundStyle(.white.opacity(0.85))
        }
    }
}

extension AppModel.TapPhase {
    var text: String {
        switch self {
        case .holding: "Keep holding…"
        case .sent(let phone): "Sent from \(phone)"
        case .failed(let tip): tip
        }
    }

    var spoken: String {
        switch self {
        case .holding: "Tap noticed. Keep holding your phone on the notch."
        case .sent(let phone): "Sent from \(phone)."
        case .failed(let tip): tip
        }
    }
}
