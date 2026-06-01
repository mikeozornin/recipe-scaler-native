import Foundation

/// Converts Socket.IO JSON payloads (`[Int]`, `[Double]`, `[NSNumber]`, …) into binary Y.Doc data.
enum YjsPayloadBytes {
    static func array(from data: Data) -> [Int] {
        data.map { Int($0) }
    }

    static func data(from value: Any?) -> Data? {
        guard let value else { return nil }

        if let data = value as? Data {
            return data
        }
        if let bytes = value as? [UInt8] {
            return Data(bytes)
        }
        if let ints = value as? [Int] {
            return Data(ints.map { UInt8(truncatingIfNeeded: $0) })
        }
        if let doubles = value as? [Double] {
            return Data(doubles.map { UInt8(truncatingIfNeeded: Int($0)) })
        }
        if let numbers = value as? [NSNumber] {
            return Data(numbers.map { UInt8(truncatingIfNeeded: $0.intValue) })
        }
        if let array = value as? [Any] {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(array.count)
            for element in array {
                guard let byte = byteValue(from: element) else { return nil }
                bytes.append(byte)
            }
            return Data(bytes)
        }

        return nil
    }

    private static func byteValue(from element: Any) -> UInt8? {
        if let value = element as? Int {
            return UInt8(truncatingIfNeeded: value)
        }
        if let value = element as? Double {
            return UInt8(truncatingIfNeeded: Int(value))
        }
        if let value = element as? NSNumber {
            return UInt8(truncatingIfNeeded: value.intValue)
        }
        return nil
    }
}
