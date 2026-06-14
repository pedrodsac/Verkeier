import Compression
import Foundation

nonisolated protocol GTFSArchiveExtracting: Sendable {
    func unzip(_ archiveURL: URL, to destination: URL) throws
}

nonisolated struct GTFSArchiveService: GTFSArchiveExtracting {
    func unzip(_ archiveURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: archiveURL)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var offset = 0
        var extractedEntries = 0

        while offset + 30 <= data.count {
            let signature = data.uint32(at: offset)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }
            guard signature == 0x04034b50 else {
                throw GTFSUpdateError.invalidArchive
            }

            let method = data.uint16(at: offset + 8)
            let compressedSize = Int(data.uint32(at: offset + 18))
            let uncompressedSize = Int(data.uint32(at: offset + 22))
            let fileNameLength = Int(data.uint16(at: offset + 26))
            let extraLength = Int(data.uint16(at: offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + fileNameLength
            let payloadStart = nameEnd + extraLength
            let payloadEnd = payloadStart + compressedSize

            guard nameEnd <= data.count, payloadEnd <= data.count else {
                throw GTFSUpdateError.invalidArchive
            }

            let rawName = String(decoding: data[nameStart..<nameEnd], as: UTF8.self)
            guard let relativePath = safeRelativePath(rawName) else {
                offset = payloadEnd
                continue
            }

            let outputURL = destination.appendingPathComponent(relativePath)
            if rawName.hasSuffix("/") {
                try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } else {
                let payload = data[payloadStart..<payloadEnd]
                let outputData: Data
                switch method {
                case 0:
                    outputData = Data(payload)
                case 8:
                    outputData = try inflate(payload, expectedSize: uncompressedSize)
                default:
                    throw GTFSUpdateError.unsupportedCompressionMethod(method)
                }

                try fileManager.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try outputData.write(to: outputURL, options: [.atomic])
                extractedEntries += 1
            }

            offset = payloadEnd
        }

        guard extractedEntries > 0 else {
            throw GTFSUpdateError.invalidArchive
        }
    }

    private func inflate(_ payload: Data.SubSequence, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }

        var destination = [UInt8](repeating: 0, count: expectedSize)
        let decodedCount = payload.withUnsafeBytes { sourceBuffer in
            compression_decode_buffer(
                &destination,
                destination.count,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                payload.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decodedCount == expectedSize else {
            throw GTFSUpdateError.invalidArchive
        }

        return Data(destination)
    }

    private func safeRelativePath(_ rawName: String) -> String? {
        let parts = rawName.split(separator: "/").map(String.init)
        guard !parts.isEmpty,
              !rawName.hasPrefix("/"),
              !parts.contains("..") else {
            return nil
        }
        return parts.joined(separator: "/")
    }
}

private extension Data {
    nonisolated func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    nonisolated func uint32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
