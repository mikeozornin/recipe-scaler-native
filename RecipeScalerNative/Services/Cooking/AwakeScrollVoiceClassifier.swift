import Foundation

enum AwakeScrollVoiceClassifier {
    static func action(
        from transcript: String,
        isFinal: Bool,
        isStablePartial: Bool = false
    ) -> AwakeScrollAction? {
        guard let chip = chip(from: transcript) else { return nil }
        if isFinal || isStablePartial { return chip.action }
        if delaysPartial(normalize(transcript)) { return nil }
        return chip.action
    }

    static func match(_ normalized: String) -> AwakeScrollAction? {
        chip(from: normalized)?.action
    }

    static func chip(from transcript: String) -> AwakeScrollVoiceChip? {
        let normalized = normalize(transcript)
        if let chip = Self.chipMap[normalized] { return chip }
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let maxN = min(3, tokens.count)
        if maxN >= 2 {
            for n in stride(from: maxN, through: 2, by: -1) {
                let tail = tokens.suffix(n).joined(separator: " ")
                if let chip = Self.chipMap[tail] { return chip }
            }
        }
        let last = tokens[tokens.count - 1]
        if Self.trailingSingletons.contains(last) {
            return Self.chipMap[last]
        }
        return nil
    }

    /// English "up"/"down" as a whole utterance can be a STT prefix ("update").
    /// RU singletons and multi-word chips are already complete whitelist hits.
    static func delaysPartial(_ normalized: String) -> Bool {
        normalized == "up" || normalized == "down"
    }

    static func tokenCount(_ transcript: String) -> Int {
        normalize(transcript)
            .split(whereSeparator: { $0.isWhitespace })
            .count
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

    private static let trailingSingletons: Set<String> = [
        "вверх",
        "выше",
        "наверх",
        "higher",
        "вниз",
        "ниже",
        "lower",
    ]

    private static let chipMap: [String: AwakeScrollVoiceChip] = [
        "вверх": .up,
        "выше": .higher,
        "наверх": .up,
        "up": .up,
        "higher": .higher,
        "прокрути вверх": .scrollUp,
        "scroll up": .scrollUp,
        "вниз": .down,
        "ниже": .lower,
        "down": .down,
        "lower": .lower,
        "прокрути вниз": .scrollDown,
        "scroll down": .scrollDown,
    ]
}

/// Debounce owner for F3.3. RU / multi-word chips fire on the first matching
/// partial; English "up"/"down" still need a stable 300 ms (or final).
struct AwakeScrollVoiceFireGate: Equatable, Sendable {
    static let stablePartialDuration: TimeInterval = 0.3

    private var lastNormalized = ""
    private var lastChangedAt: Date?

    mutating func action(
        from transcript: String,
        isFinal: Bool,
        now: Date
    ) -> AwakeScrollAction? {
        let normalized = AwakeScrollVoiceClassifier.normalize(transcript)
        if normalized != lastNormalized {
            lastNormalized = normalized
            lastChangedAt = now
        }
        let elapsed = lastChangedAt.map { now.timeIntervalSince($0) } ?? 0
        let isStablePartial = elapsed >= Self.stablePartialDuration
        return AwakeScrollVoiceClassifier.action(
            from: transcript,
            isFinal: isFinal,
            isStablePartial: isStablePartial
        )
    }

    mutating func reset() {
        lastNormalized = ""
        lastChangedAt = nil
    }
}
