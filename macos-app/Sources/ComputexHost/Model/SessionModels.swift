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

enum SessionCloneSource: String, CaseIterable, Identifiable {
    case base
    case primary
    case selected

    var id: String { rawValue }

    var label: String {
        switch self {
        case .base:
            return "Base VM"
        case .primary:
            return "Primary VM"
        case .selected:
            return "Selected VM"
        }
    }
}
