import Foundation

enum AppLog {
    static func info(_ message: String) {
        write(prefix: "INFO", message: message)
    }

    static func error(_ message: String) {
        write(prefix: "ERROR", message: message)
    }

    static func writeLine(_ line: String) {
        print(line)
        NSLog("%@", line)
    }

    private static func write(prefix: String, message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(prefix)] \(message)"
        writeLine(line)
    }
}
