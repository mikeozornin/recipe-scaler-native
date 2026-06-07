import Foundation
import YrsC

/// Builds `YInput` values for yrs write APIs (`ymap_insert`, `yarray_insert_range`, …).
///
/// `yinput_string` and `yinput_ymap` borrow pointers — they must stay valid until the yrs
/// insert call returns. `YrsInput.withMaterialized` keeps all strdup'd strings and heap-allocated
/// `YInput` / key buffers alive for the duration of `body`.
enum YrsInput {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case map([(String, YrsInput)])
    case yarray([YrsInput])
    /// JSON-array of strings stored as a plain value (not a nested `Y.Array` shared type).
    /// Used by recipe entry `folderIds` (see web `setRecipeFolderIds`).
    case jsonStringArray([String])

    /// Materializes a `YInput` tree and keeps every borrowed pointer alive through `body`.
    static func withMaterialized<R>(_ input: YrsInput, _ body: (YInput) -> R) -> R {
        let arena = Arena()
        defer { arena.releaseAll() }
        let yInput = arena.materialize(input)
        return body(yInput)
    }

    static func ingredientMap(_ ingredient: IngredientData) -> YrsInput {
        var entries: [(String, YrsInput)] = [
            ("id", .string(ingredient.id)),
            ("name", .string(ingredient.name)),
            ("order", .int(Int64(ingredient.order))),
            ("unit", .string(ingredient.unit)),
            ("isSeparator", .bool(ingredient.isSeparator)),
        ]
        if ingredient.hasQuantity,
           let numeric = Double(ingredient.originalAmount.replacingOccurrences(of: ",", with: ".")) {
            entries.append(("originalAmount", .double(numeric)))
            entries.append(("amount", .double(numeric)))
        } else if ingredient.hasQuantity {
            entries.append(("originalAmount", .string(ingredient.originalAmount)))
            entries.append(("amount", .string(ingredient.amount.isEmpty ? ingredient.originalAmount : ingredient.amount)))
        }
        if let calories = ingredient.calories { entries.append(("calories", .double(calories))) }
        if let protein = ingredient.protein { entries.append(("protein", .double(protein))) }
        if let fat = ingredient.fat { entries.append(("fat", .double(fat))) }
        if let carbs = ingredient.carbs { entries.append(("carbs", .double(carbs))) }
        if let weight = ingredient.weight { entries.append(("weight", .double(weight))) }
        return .map(entries)
    }

    // MARK: - Arena

    private final class Arena {
        private var ownedCString: [UnsafeMutablePointer<CChar>] = []
        private var ownedKeyBuffers: [UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>] = []
        private var ownedValueBuffers: [UnsafeMutablePointer<YInput>] = []

        func persist(_ string: String) -> UnsafeMutablePointer<CChar> {
            // Re-encode to guarantee valid UTF-8 for yffi (`to_str().unwrap()` on Y_JSON_STR).
            let utf8 = String(decoding: Data(string.utf8), as: UTF8.self)
            let ptr = utf8.withCString { strdup($0)! }
            ownedCString.append(ptr)
            return ptr
        }

        func materialize(_ input: YrsInput) -> YInput {
            switch input {
            case .string(let value):
                return yinput_string(persist(value))
            case .int(let value):
                return yinput_long(value)
            case .double(let value):
                return yinput_float(value)
            case .bool(let value):
                return yinput_bool(value ? 1 : 0)
            case .map(let entries):
                guard !entries.isEmpty else {
                    return yinput_ymap(nil, nil, 0)
                }
                let count = entries.count
                let keysPtr = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: count)
                let valuesPtr = UnsafeMutablePointer<YInput>.allocate(capacity: count)
                ownedKeyBuffers.append(keysPtr)
                ownedValueBuffers.append(valuesPtr)
                for index in 0..<count {
                    keysPtr[index] = persist(entries[index].0)
                    valuesPtr[index] = materialize(entries[index].1)
                }
                return yinput_ymap(keysPtr, valuesPtr, UInt32(count))
            case .yarray(let items):
                guard !items.isEmpty else {
                    return yinput_yarray(nil, 0)
                }
                let count = items.count
                let valuesPtr = UnsafeMutablePointer<YInput>.allocate(capacity: count)
                ownedValueBuffers.append(valuesPtr)
                for index in 0..<count {
                    valuesPtr[index] = materialize(items[index])
                }
                return yinput_yarray(valuesPtr, UInt32(count))
            case .jsonStringArray(let values):
                // Stored as a JSON-array value (Y_JSON_ARR) on the parent map,
                // matching how the web client writes `folderIds: string[]`.
                if values.isEmpty {
                    return yinput_json_array(nil, 0)
                }
                let count = values.count
                let valuesPtr = UnsafeMutablePointer<YInput>.allocate(capacity: count)
                ownedValueBuffers.append(valuesPtr)
                for index in 0..<count {
                    valuesPtr[index] = yinput_string(persist(values[index]))
                }
                return yinput_json_array(valuesPtr, UInt32(count))
            }
        }

        func releaseAll() {
            for ptr in ownedCString {
                free(ptr)
            }
            ownedCString.removeAll()

            for ptr in ownedKeyBuffers {
                ptr.deallocate()
            }
            ownedKeyBuffers.removeAll()

            for ptr in ownedValueBuffers {
                ptr.deallocate()
            }
            ownedValueBuffers.removeAll()
        }
    }
}