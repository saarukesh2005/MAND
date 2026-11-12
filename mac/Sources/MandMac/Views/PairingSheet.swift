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
                    Step(number: 1, text: "On your phone, open M’AND and tap “Pair with Mac”.")
                    Step(number: 2, text: "Scan this code. (Your phone’s camera app may also open it.)")
                    Step(number: 3, text: "Check the codes match, then click Allow here.")
                }
                .frame(maxWidth: 320, alignment: .leading)

                DisclosureGroup("Don’t have M’AND on your phone yet?") {
                    VStack(spacing: 8) {
                        if let image = QRCode.image(for: AppInfo.downloadPage) {
                            Image(nsImage: image).interpolation(.none).resizable()
                                .frame(width: 140, height: 140).padding(8)
                                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityLabel("QR code for the phone app download page")
                        }
                        Text("Scan this with your phone’s camera to download the app, install it, then scan the pairing code above.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
                .frame(maxWidth: 320)

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
        .frame(width: 420)
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
