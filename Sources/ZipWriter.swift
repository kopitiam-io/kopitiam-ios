import Foundation

/// Minimal ZIP archive writer (STORE method, no compression). Enough to package
/// Office Open XML containers (.docx / .xlsx), which are ZIP files. No external
/// dependencies — writes the local file headers, central directory, and EOCD by
/// hand. Store (uncompressed) keeps the code small and is fully valid ZIP; Word
/// and Excel open store-only OOXML packages without complaint.
enum ZipWriter {

    struct Entry {
        let name: String
        let data: Data
        let crc: UInt32
        let offset: UInt32
    }

    /// Write `entries` (name, bytes) as a ZIP archive at `url`.
    static func write(_ url: URL, entries: [(String, Data)]) throws {
        var archive = Data()
        var directory: [Entry] = []

        for (name, data) in entries {
            let crc = crc32(data)
            let offset = UInt32(archive.count)
            let nameBytes = Array(name.utf8)

            // Local file header.
            archive.append(le32(0x04034b50))          // signature
            archive.append(le16(20))                  // version needed
            archive.append(le16(0))                   // flags
            archive.append(le16(0))                   // method: 0 = store
            archive.append(le16(0))                   // mod time
            archive.append(le16(0))                   // mod date
            archive.append(le32(crc))                 // crc-32
            archive.append(le32(UInt32(data.count)))  // compressed size
            archive.append(le32(UInt32(data.count)))  // uncompressed size
            archive.append(le16(UInt16(nameBytes.count)))
            archive.append(le16(0))                   // extra length
            archive.append(contentsOf: nameBytes)
            archive.append(data)

            directory.append(Entry(name: name, data: data, crc: crc, offset: offset))
        }

        let centralStart = UInt32(archive.count)
        for e in directory {
            let nameBytes = Array(e.name.utf8)
            archive.append(le32(0x02014b50))          // central dir signature
            archive.append(le16(20))                  // version made by
            archive.append(le16(20))                  // version needed
            archive.append(le16(0))                   // flags
            archive.append(le16(0))                   // method: store
            archive.append(le16(0))                   // mod time
            archive.append(le16(0))                   // mod date
            archive.append(le32(e.crc))               // crc-32
            archive.append(le32(UInt32(e.data.count)))// compressed size
            archive.append(le32(UInt32(e.data.count)))// uncompressed size
            archive.append(le16(UInt16(nameBytes.count)))
            archive.append(le16(0))                   // extra length
            archive.append(le16(0))                   // comment length
            archive.append(le16(0))                   // disk number start
            archive.append(le16(0))                   // internal attrs
            archive.append(le32(0))                   // external attrs
            archive.append(le32(e.offset))            // local header offset
            archive.append(contentsOf: nameBytes)
        }
        let centralSize = UInt32(archive.count) - centralStart

        // End of central directory record.
        archive.append(le32(0x06054b50))
        archive.append(le16(0))                       // disk number
        archive.append(le16(0))                       // disk with central dir
        archive.append(le16(UInt16(directory.count))) // entries on this disk
        archive.append(le16(UInt16(directory.count))) // total entries
        archive.append(le32(centralSize))
        archive.append(le32(centralStart))
        archive.append(le16(0))                       // comment length

        try archive.write(to: url)
    }

    // MARK: - Little-endian encoders

    private static func le16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]
    }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff),
         UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    // MARK: - CRC-32 (IEEE 802.3), table-driven

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func append(_ bytes: [UInt8]) {
        append(contentsOf: bytes)
    }
}
