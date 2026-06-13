//
//  RecipeEntity.swift
//  RecipeScalerNative
//

import AppIntents

struct RecipeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Recipe"
    static var defaultQuery = RecipeEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct RecipeEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RecipeEntity] {
        let snapshots = RecipeSnapshotStore.load()
        return identifiers.compactMap { id in
            snapshots.first(where: { $0.id == id }).map {
                RecipeEntity(id: $0.id, name: $0.name)
            }
        }
    }

    func suggestedEntities() async throws -> [RecipeEntity] {
        RecipeSnapshotStore.load().map { RecipeEntity(id: $0.id, name: $0.name) }
    }
}
