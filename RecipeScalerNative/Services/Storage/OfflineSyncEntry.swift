import Foundation
import GRDB

struct OfflineSyncEntry: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "offline_sync_queue"

    var id: Int64?
    var docKey: String
    var recipeId: String
    var yjsUpdate: Data
    var createdAt: String
    var attemptCount: Int
}