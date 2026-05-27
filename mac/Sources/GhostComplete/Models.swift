import AppKit
import Foundation

struct AppContext: Codable, Equatable, Sendable {
    let bundleId: String
    let name: String
}

struct SelectionRange: Codable, Equatable, Sendable {
    let location: Int
    let length: Int
}

struct CompleteRequest: Codable, Equatable, Sendable {
    let requestId: String
    let context: String
    let app: AppContext
    let selection: SelectionRange?
}

struct CompleteResponse: Codable, Equatable, Sendable {
    let requestId: String
    let completion: String
    let model: String
    let latencyMs: Int
}

struct LearnRequest: Codable, Equatable, Sendable {
    let requestId: String
    let event: String
    let contextHash: String
    let suggestion: String
    let app: AppContext
}

struct FocusSnapshot: Sendable {
    let context: String
    let caretRect: CGRect?
    let app: AppContext
    let selection: SelectionRange?
}

struct Profile: Codable, Equatable, Sendable {
    var name: String
    var role: String
    var projects: [String]
    var vocabulary: [String]
    var tone: String
    var languages: [String]
    var peopleOrgs: [String]
    var neverSay: [String]

    static let empty = Profile(
        name: "",
        role: "",
        projects: [],
        vocabulary: [],
        tone: "",
        languages: ["en"],
        peopleOrgs: [],
        neverSay: []
    )
}
