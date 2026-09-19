import Foundation

enum AwakeScrollVoiceClassifier {
    static func action(
        from transcript: String,
        isFinal: Bool,
        isStablePartial: Bool = false
    ) -> AwakeScrollAction? {
        guard isFinal || isStablePartial else { return nil }
        return match(normalize(transcript))
    }

    static func match(_ normalized: String) -> AwakeScrollAction? {
        chip(from: normalized)?.action
    }

    static func chip(from transcript: String) -> AwakeScrollVoiceChip? {
        let normalized = normalize(transcript)
        if let chip = Self.chipMap[normalized] { return chip }
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let maxN = min(3, tokens.count)
        guard maxN > 0 else { return nil }
        for n in 1...maxN {
            let tail = tokens.suffix(n).joined(separator: " ")
            if let chip = Self.chipMap[tail] { return chip }
        }
        return nil
    }

    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.lowercased()
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        while let last = text.last, ".!?…".contains(last) {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static let chipMap: [String: AwakeScrollVoiceChip] = [
        "вверх": .up,
        "выше": .up,
        "наверх": .up,
        "up": .up,
        "прокрути вверх": .scrollUp,
        "scroll up": .scrollUp,
        "вниз": .down,
        "ниже": .down,
        "down": .down,
        "прокрути вниз": .scrollDown,
        "scroll down": .scrollDown,
    ]
}
