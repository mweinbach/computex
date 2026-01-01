import Foundation

enum BridgeMessageType: String, Codable {
    case modelStream
    case toolCall
    case toolResult
    case stdout
    case stderr
    case event
    case screenshot
    case status
}

struct BridgeMessage: Codable, Identifiable {
    let id: UUID
    let type: BridgeMessageType
    let timestamp: Date
    let payload: String

    init(type: BridgeMessageType, payload: String) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.payload = payload
    }
}
