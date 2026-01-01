import Foundation

struct VMCheckpoint: Identifiable, Hashable, Codable {
    let id: String
    let sessionID: String
    let name: String
    let createdAt: Date
    let hasState: Bool

    init(id: String, sessionID: String, name: String, createdAt: Date, hasState: Bool) {
        self.id = id
        self.sessionID = sessionID
        self.name = name
        self.createdAt = createdAt
        self.hasState = hasState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        hasState = (try? container.decode(Bool.self, forKey: .hasState)) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case name
        case createdAt
        case hasState
    }
}
