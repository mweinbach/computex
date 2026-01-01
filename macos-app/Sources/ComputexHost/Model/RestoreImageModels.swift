import Foundation

enum RestoreImageSource: String, Codable {
    case latest
    case manual
}

struct RestoreImageSelection: Equatable {
    let url: URL
    let source: RestoreImageSource
    let label: String
    let storedID: String?
}

struct IPSWMetadata {
    static func versionLabel(for url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        let pattern = #"\d+\.\d+(?:\.\d+)?"#
        if let range = name.range(of: pattern, options: .regularExpression) {
            return String(name[range])
        }
        return nil
    }
}
