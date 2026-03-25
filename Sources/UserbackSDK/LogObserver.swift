import Foundation

#if canImport(UIKit) && canImport(WebKit)

@MainActor
public final class LogObserver {
    public static let shared = LogObserver()

    private var pipe: Pipe?
    private var originalStdout: Int32?
    private var originalStderr: Int32?

    private init() {}

    public func start() {
        guard pipe == nil else { return }

        let newPipe = Pipe()
        pipe = newPipe

        // Keep copies so stdout/stderr can be restored on stop.
        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)

        dup2(newPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(newPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        let mirroredStdoutFD = originalStdout

        newPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            // Mirror captured output back to original stdout so Xcode console still shows logs.
            if let stdoutFD = mirroredStdoutFD {
                data.withUnsafeBytes { buffer in
                    guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    var bytesRemaining = buffer.count
                    var offset = 0

                    while bytesRemaining > 0 {
                        let written = write(stdoutFD, base.advanced(by: offset), bytesRemaining)
                        if written <= 0 { break }
                        bytesRemaining -= written
                        offset += written
                    }
                }
            }

            guard let raw = String(data: data, encoding: .utf8) else {
                return
            }

            let messages = raw
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for message in messages {
                // Avoid feedback loops from SDK/internal observer logs.
                if message.hasPrefix("UserbackSDK:") ||
                    message.hasPrefix("LogObserver") ||
                    message == "================" {
                    continue
                }

                // Ignore noisy Apple system logs that are not app-level diagnostics.
                if message.hasPrefix("OSLOG-") ||
                    message.localizedCaseInsensitiveContains("RemoteTextInput") ||
                    message.localizedCaseInsensitiveContains("RTILog") ||
                    message.localizedCaseInsensitiveContains("NSAutoresizingMaskLayoutConstraint") ||
                    message.localizedCaseInsensitiveContains("NSLayoutConstraint") ||
                    message.localizedCaseInsensitiveContains("Unable to simultaneously satisfy constraints") ||
                    message.localizedCaseInsensitiveContains("UIViewAlertForUnsatisfiableConstraints") ||
                    message.localizedCaseInsensitiveContains("Probably at least one of the constraints") ||
                    message.localizedCaseInsensitiveContains("Will attempt to recover by breaking constraint") ||
                    message.localizedCaseInsensitiveContains("UIConstraintBasedLayoutDebugging category on UIView") ||
                    message.localizedCaseInsensitiveContains("_UIToolbarContentView") ||
                    message.localizedCaseInsensitiveContains("_UIButtonBarStackView") {
                    continue
                }

                // Trim whitespace and collapse multiple spaces
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

                guard !trimmed.isEmpty else { continue }

                let event: [String: Any] = [
                    "type": "log",
                    "message": trimmed
                ]

                Task { @MainActor in
                    UserbackSDK.shared.sendNativeEvent(event)
                }
            }
        }

        print("LogObserver started")
    }

    public func stop() {
        pipe?.fileHandleForReading.readabilityHandler = nil

        if let originalStdout {
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            self.originalStdout = nil
        }

        if let originalStderr {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            self.originalStderr = nil
        }

        pipe = nil
        print("LogObserver stopped")
    }
}

#endif
