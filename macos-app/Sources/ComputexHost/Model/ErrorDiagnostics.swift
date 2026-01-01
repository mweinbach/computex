import Foundation

enum ErrorDiagnostics {
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var details: [String] = []
        details.append("domain=\(nsError.domain)")
        details.append("code=\(nsError.code)")

        if let reason = nsError.localizedFailureReason {
            details.append("reason=\(reason)")
        }
        if let suggestion = nsError.localizedRecoverySuggestion {
            details.append("suggestion=\(suggestion)")
        }
        if let debug = nsError.userInfo[NSDebugDescriptionErrorKey] as? String {
            details.append("debug=\(debug)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlying=\(underlying.domain)/\(underlying.code): \(underlying.localizedDescription)")
        }

        return details.joined(separator: ", ")
    }
}
