import Foundation
import YrsC

/// Builds `YInput` values for yrs write APIs (`ymap_insert`, `yarray_insert_range`, …).
///
/// `yinput_string` does **not** copy the C string — it only stores the pointer until `ymap_insert`
/// runs. All string pointers must stay alive through the insert call (see `YrsInputArena`).
enum YrsInput {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case map([(String, YrsInput)])
    case yarray([YrsInput])

    /// Materializes a `YInput` tree and keeps every borrowed C string alive for the duration of `body`.
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

    // MARK: - Arena (owns strdup'd C strings until releaseAll)

    private final class Arena {
        private var ownedCString: [UnsafeMutablePointer<CChar>] = []

        func persist(_ string: String) -> UnsafeMutablePointer<CChar> {
            let ptr = string.withCString { strdup($0)! }
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
                var keyPtrs: [UnsafeMutablePointer<CChar>?] = entries.map { persist($0.0) }
                var values = entries.map { materialize($0.1) }
                return values.withUnsafeMutableBufferPointer { valueBuf in
                    keyPtrs.withUnsafeMutableBufferPointer { keyBuf in
                        yinput_ymap(keyBuf.baseAddress, valueBuf.baseAddress, UInt32(entries.count))
                    }
                }
            case .yarray(let items):
                if items.isEmpty {
                    return yinput_yarray(nil, 0)
                }
                var values = items.map { materialize($0) }
                return values.withUnsafeMutableBufferPointer { buf in
                    yinput_yarray(buf.baseAddress, UInt32(items.count))
                }
            }
        }

        func releaseAll() {
            for ptr in ownedCString {
                free(ptr)
            }
            ownedCString.removeAll()
        }
    }
}