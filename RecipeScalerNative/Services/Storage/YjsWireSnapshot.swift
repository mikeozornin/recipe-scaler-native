import Foundation
import GRDB

/// Last known yjs wire-format full document state for server push (v3 description path).
struct YjsWireSnapshot: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "yjs_wire_snapshots"

    var docKey: String
    var state: Data
    var updatedAt: String
}
