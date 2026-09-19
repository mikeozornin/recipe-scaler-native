import Foundation

enum AwakeHandsFreeStorage {
    static let legacyKey = "awakeHandsFreeEnabled"
    static let voiceKey = "awakeHandsFreeVoiceEnabled"
    static let handKey = "awakeHandsFreeHandEnabled"
    static let faceKey = "awakeHandsFreeFaceEnabled"
    static let migrationKey = "awakeHandsFreeChannelMigrationDone"

    /// Rev 3 AppStorage key; not a source of truth after migration.
    static let key = voiceKey

    static var defaults: UserDefaults = .standard

    static var voiceEnabled: Bool {
        get {
            migrateIfNeeded()
            return defaults.bool(forKey: voiceKey)
        }
        set {
            migrateIfNeeded()
            defaults.set(newValue, forKey: voiceKey)
        }
    }

    static var handEnabled: Bool {
        get {
            migrateIfNeeded()
            return defaults.bool(forKey: handKey)
        }
        set {
            setHandEnabled(newValue)
        }
    }

    static var faceEnabled: Bool {
        get {
            migrateIfNeeded()
            return defaults.bool(forKey: faceKey)
        }
        set {
            setFaceEnabled(newValue)
        }
    }

    static var isAnyEnabled: Bool {
        voiceEnabled || handEnabled || faceEnabled
    }

    static func setHandEnabled(_ value: Bool) {
        migrateIfNeeded()
        defaults.set(value, forKey: handKey)
        if value {
            defaults.set(false, forKey: faceKey)
        }
    }

    static func setFaceEnabled(_ value: Bool) {
        migrateIfNeeded()
        defaults.set(value, forKey: faceKey)
        if value {
            defaults.set(false, forKey: handKey)
        }
    }

    static func migrateIfNeeded(trueDepthAvailable: Bool? = nil) {
        if defaults.object(forKey: migrationKey) != nil { return }
        let hasNewKeys = defaults.object(forKey: voiceKey) != nil
            || defaults.object(forKey: handKey) != nil
            || defaults.object(forKey: faceKey) != nil
        if !hasNewKeys, (defaults.object(forKey: legacyKey) as? Bool) == true {
            defaults.set(true, forKey: voiceKey)
            let face = trueDepthAvailable ?? false
            if face {
                defaults.set(true, forKey: faceKey)
                defaults.set(false, forKey: handKey)
            } else {
                defaults.set(true, forKey: handKey)
                defaults.set(false, forKey: faceKey)
            }
        }
        defaults.set(true, forKey: migrationKey)
    }
}
