import Foundation

enum GhostTextSegmenter {
    static func splitFirstWord(from suggestion: String) -> (accepted: String, remaining: String) {
        guard !suggestion.isEmpty else {
            return ("", "")
        }

        var index = suggestion.startIndex
        while index < suggestion.endIndex, suggestion[index].isWhitespace {
            index = suggestion.index(after: index)
        }

        if index == suggestion.endIndex {
            return (suggestion, "")
        }

        var end = index
        while end < suggestion.endIndex, !suggestion[end].isWhitespace {
            end = suggestion.index(after: end)
        }

        return (String(suggestion[..<end]), String(suggestion[end...]))
    }
}
