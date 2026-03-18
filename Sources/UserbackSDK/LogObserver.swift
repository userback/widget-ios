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

        newPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let raw = String(data: data, encoding: .utf8) else {
                return
            }

            let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }

            let event: [String: Any] = [
                "type": "console",
                "message": message
            ]

            Task { @MainActor in
                UserbackSDK.shared.sendNativeEvent(event)
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
