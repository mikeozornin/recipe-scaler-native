//
//  Gunzip.swift
//  RecipeScalerCore
//

import Foundation
import zlib

public enum Gunzip {
    public static func decompress(_ data: Data, fileName: String = "") throws -> Data {
        guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else {
            throw ThirdPartyImportError.gzipFailed(fileName: fileName)
        }

        var stream = z_stream()
        var status = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else {
            throw ThirdPartyImportError.gzipFailed(fileName: fileName)
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 65_536

        try data.withUnsafeBytes { rawBuffer in
            guard let inputPointer = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw ThirdPartyImportError.gzipFailed(fileName: fileName)
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPointer)
            stream.avail_in = uInt(data.count)

            var buffer = [UInt8](repeating: 0, count: chunkSize)
            repeat {
                stream.next_out = UnsafeMutablePointer<Bytef>(&buffer)
                stream.avail_out = uInt(chunkSize)
                status = inflate(&stream, Z_SYNC_FLUSH)
                if status != Z_OK && status != Z_STREAM_END {
                    throw ThirdPartyImportError.gzipFailed(fileName: fileName)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
            } while status != Z_STREAM_END
        }

        guard !output.isEmpty else {
            throw ThirdPartyImportError.gzipFailed(fileName: fileName)
        }
        return output
    }
}
