import AVFoundation
import CoreMedia
import Foundation
import MandCore

/// Shows a phone's screen sent over `screen.v1` (built-in Wi-Fi mirroring, view only).
/// Frames arrive on the server queue and are decoded by macOS (AVSampleBufferDisplayLayer).
public final class ScreenMirror: @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        case started(phone: Fingerprint, width: Int, height: Int)
        case firstPicture(phone: Fingerprint)
        case stopped(phone: Fingerprint, reason: String)
    }

    /// The layer the UI displays. Created on the main thread with the mirror.
    public nonisolated(unsafe) let layer: AVSampleBufferDisplayLayer
    private let queue = DispatchQueue(label: "dev.mand.mac.screen", qos: .userInteractive)
    private let onEvent: @Sendable (Event) -> Void
    private var depacketizer = H264Depacketizer()
    private var phone: Fingerprint?
    private var waitingForKey = true
    private var showedPicture = false

    @MainActor
    public init(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
        layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    /// A screen.* message from `phone` (any thread).
    public func handle(_ message: Message, from phone: Fingerprint) {
        queue.async { self.receive(message, from: phone) }
    }

    /// Forget the current session (the user pressed Stop, or the phone disconnected).
    public func reset() {
        queue.async { self.clear() }
    }

    private func receive(_ message: Message, from sender: Fingerprint) {
        switch message {
        case .screenStart(let width, let height):
            clear()
            phone = sender
            onEvent(.started(phone: sender, width: width, height: height))
        case .screenFrame(_, let key, let data):
            guard sender == phone else { return }
            if waitingForKey && !key { return } // a picture can only start at a key frame
            do {
                guard let sample = try depacketizer.sampleBuffer(for: data, key: key) else { return }
                waitingForKey = false
                if !showedPicture {
                    showedPicture = true
                    onEvent(.firstPicture(phone: sender))
                }
                // Decoding and display happen in the layer, which belongs to the main thread.
                nonisolated(unsafe) let frame = sample
                let layer = self.layer
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if layer.status == .failed { layer.flush() }
                        layer.enqueue(frame)
                    }
                }
            } catch {
                waitingForKey = true // drop until the next key frame repairs the picture
            }
        case .screenStop(let reason):
            guard sender == phone else { return }
            clear()
            onEvent(.stopped(phone: sender, reason: reason))
        default:
            break
        }
    }

    private func clear() {
        phone = nil
        depacketizer = H264Depacketizer()
        waitingForKey = true
        showedPicture = false
        let layer = self.layer
        DispatchQueue.main.async { MainActor.assumeIsolated { layer.flushAndRemoveImage() } }
    }
}
