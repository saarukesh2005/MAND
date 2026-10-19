import MandMacKit
import SwiftUI

/// Shows the one-time pairing QR code with a live countdown.
struct PairingSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Text("Pair your Android phone").font(.title2.weight(.semibold))

            if let invitation = model.invitation {
                if let image = QRCode.image(for: invitation.url) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Pairing QR code")
                } else {
                    Text("Couldn’t draw the QR code.").foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Step(number: 1, text: "Open M’AND on your phone.")
                    Step(number: 2, text: "Tap “Pair with Mac” and scan this code.")
                    Step(number: 3, text: "Approve the phone here when asked.")
                }
                .frame(maxWidth: 300, alignment: .leading)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(invitation.expiresAt) - Int(context.date.timeIntervalSince1970))
                    Text("Code expires in \(remaining / 60):\(String(format: "%02d", remaining % 60)) · works once")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Mac security code: \(invitation.fingerprint.shortDisplay)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Button("Cancel") { model.cancelPairing() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 400)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.quaternary))
            Text(text)
        }
    }
}
