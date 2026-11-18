import MandCore
import MandMacKit
import SwiftUI

struct NotificationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.isConnected {
                ContentUnavailableView("Phone not connected", systemImage: "bell.slash",
                                       description: Text("Phone notifications appear here while your phone is connected."))
            } else if !model.phoneSupports(Feature.notifications) {
                ContentUnavailableView("Update M’AND on your phone", systemImage: "bell.slash",
                                       description: Text("This version of the phone app can’t share notifications."))
            } else if model.notifications.isEmpty {
                ContentUnavailableView {
                    Label("No notifications", systemImage: "bell")
                } description: {
                    Text("To see notifications here, open M’AND on your phone, turn on “Show phone notifications on Mac” and choose which apps to share. Nothing is shared until you do.")
                }
            } else {
                List {
                    ForEach(model.notifications) { notification in
                        NotificationRow(notification: notification)
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            if !model.notifications.isEmpty {
                Button("Clear All") { model.clearNotifications() }
            }
        }
    }
}

private struct NotificationRow: View {
    @Environment(AppModel.self) private var model
    let notification: PhoneNotification

    @Environment(UIState.self) private var ui

    private var replyState: AppModel.ReplyState? { model.replyStates[notification.key] }
    private var draft: String { ui.replyDrafts[notification.key] ?? "" }

    /// A plain binding rather than `$ui.replyDrafts[key, default:]`: a key path can't carry a
    /// defaulted subscript, and this project can't use `@State` (its macro needs Xcode).
    private var draftBinding: Binding<String> {
        Binding(get: { ui.replyDrafts[notification.key] ?? "" },
                set: { ui.replyDrafts[notification.key] = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(notification.appName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(Date(timeIntervalSince1970: Double(notification.time) / 1000), style: .time)
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    if let title = notification.title { Text(title).font(.body.weight(.medium)) }
                    if let text = notification.text { Text(text).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Spacer()
                Button {
                    model.dismissNotification(notification)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss on the phone too")
                .accessibilityLabel("Dismiss notification")
            }
            .accessibilityElement(children: .combine)

            if notification.canReply { replyBox }
        }
        .padding(.vertical, 4)
    }

    /// Only for notifications whose own app offers a reply box; the phone types into that box for us.
    @ViewBuilder private var replyBox: some View {
        HStack(spacing: 8) {
            TextField("Reply to \(notification.appName)…", text: draftBinding, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
                .accessibilityLabel("Reply to \(notification.appName)")
            Button("Send", action: send)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replyState == .sending)
        }
        if let message = replyState?.message {
            Text(message)
                .font(.caption)
                .foregroundStyle(replyState == .sent || replyState == .sending ? Color.secondary : Color.red)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.replyToNotification(notification, text: text)
        ui.replyDrafts[notification.key] = nil
    }
}
