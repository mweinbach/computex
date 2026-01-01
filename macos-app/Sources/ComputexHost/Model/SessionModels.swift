import Foundation

struct VMSessionSummary: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let kind: SessionKind
}

enum SessionKind: String, Codable {
    case primary
    case disposable

    var label: String {
        switch self {
        case .primary:
            return "Primary"
        case .disposable:
            return "Disposable"
        }
    }
}
