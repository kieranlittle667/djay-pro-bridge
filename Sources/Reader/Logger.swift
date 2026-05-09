import DjayBridge
import Foundation

final class Logger {
    static let shared = Logger()

    private let queue = DispatchQueue(label: "reader-logger")
    private var fileHandle: FileHandle?
    private var enabled = false

    private init() {}

    func configure(path: String?) {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            fileHandle = try FileHandle(forWritingTo: url)
            try fileHandle?.seekToEnd()
            enabled = true
            log("LOGGER START path=\(path)")
        } catch {
            printError("⚠️ Failed to open log file \(path): \(error)")
        }
    }

    func log(_ message: String) {
        guard enabled, let fileHandle else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"
        queue.async {
            do {
                try fileHandle.write(contentsOf: Data(line.utf8))
            } catch {
                printError("⚠️ Failed writing log file: \(error)")
            }
        }
    }
}
