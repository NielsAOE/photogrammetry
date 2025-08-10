import Foundation

/// Minimal ZIP writer (store-only). Streams file reads to bound memory and computes CRC incrementally.
enum SimpleZip {
    struct ZipError: Error { let message: String }

    static func zipFolder(at folder: URL, zipName: String) throws -> URL {
        let fm = FileManager.default
        let outURL = fm.temporaryDirectory.appendingPathComponent(zipName)
        if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
        guard let out = OutputStream(url: outURL, append: false) else { throw ZipError(message: "Cannot open output stream") }
        out.open(); defer { out.close() }

        let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == false }

        var central: [Central] = []
        var offset: UInt32 = 0
        for file in files {
            let name = file.lastPathComponent
            let nameData = name.data(using: .utf8) ?? Data()
            let (size, crc) = try fileSizeAndCRC(url: file)
            let lh = LocalHeader(nameLength: UInt16(nameData.count), uncompressedSize: UInt32(size), crc32: crc)
            let localOffset = offset
            offset += try writeLocalHeader(lh, nameData: nameData, to: out)
            offset += try writeFileDataStreaming(file: file, to: out)
            let c = Central(name: name, header: lh, localHeaderOffset: localOffset)
            central.append(c)
        }
        let cdStart = offset
        for c in central { offset += try writeCentralDirectory(c, to: out) }
        let cdSize = offset - cdStart
        _ = try writeEndOfCentralDirectory(count: UInt16(central.count), size: cdSize, offset: cdStart, to: out)
        return outURL
    }

    private struct LocalHeader { let nameLength: UInt16; let uncompressedSize: UInt32; let crc32: UInt32 }
    private struct Central { let name: String; let header: LocalHeader; let localHeaderOffset: UInt32 }

    private static func writeLocalHeader(_ h: LocalHeader, nameData: Data, to out: OutputStream) throws -> UInt32 {
        var b: [UInt8] = []
        b += le32(0x04034b50); b += le16(20); b += le16(0); b += le16(0); b += le16(0); b += le16(0)
        b += le32(h.crc32); b += le32(h.uncompressedSize); b += le32(h.uncompressedSize)
        b += le16(h.nameLength); b += le16(0)
        let headerLen = try write(b, to: out); _ = try write(Array(nameData), to: out)
        return UInt32(headerLen + nameData.count)
    }
    private static func writeCentralDirectory(_ c: Central, to out: OutputStream) throws -> UInt32 {
        let nameData = c.name.data(using: .utf8) ?? Data()
        var b: [UInt8] = []
        b += le32(0x02014b50); b += le16(20); b += le16(20); b += le16(0); b += le16(0); b += le16(0); b += le16(0)
        b += le32(c.header.crc32); b += le32(c.header.uncompressedSize); b += le32(c.header.uncompressedSize)
        b += le16(UInt16(nameData.count)); b += le16(0); b += le16(0); b += le16(0); b += le16(0); b += le32(0)
        b += le32(c.localHeaderOffset)
        let headerLen = try write(b, to: out); _ = try write(Array(nameData), to: out)
        return UInt32(headerLen + nameData.count)
    }
    private static func writeEndOfCentralDirectory(count: UInt16, size: UInt32, offset: UInt32, to out: OutputStream) throws -> UInt32 {
        var b: [UInt8] = []
        b += le32(0x06054b50); b += le16(0); b += le16(0); b += le16(count); b += le16(count)
        b += le32(size); b += le32(offset); b += le16(0)
        return UInt32(try write(b, to: out))
    }

    private static func writeFileDataStreaming(file: URL, to out: OutputStream) throws -> UInt32 {
        guard let inp = InputStream(url: file) else { return 0 }
        inp.open(); defer { inp.close() }
        let bufSize = 64 * 1024
        var total: UInt32 = 0
        var buffer = [UInt8](repeating: 0, count: bufSize)
        while inp.hasBytesAvailable {
            let n = inp.read(&buffer, maxLength: bufSize)
            if n <= 0 { break }
            total += UInt32(try write(Array(buffer.prefix(n)), to: out))
        }
        return total
    }

    private static func fileSizeAndCRC(url: URL) throws -> (Int64, UInt32) {
        guard let inp = InputStream(url: url) else { throw ZipError(message: "Cannot open input") }
        inp.open(); defer { inp.close() }
        var crc: UInt32 = 0xFFFF_FFFF
        let bufSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufSize)
        var size: Int64 = 0
        while inp.hasBytesAvailable {
            let n = inp.read(&buffer, maxLength: bufSize)
            if n <= 0 { break }
            size += Int64(n)
            for i in 0..<n { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(buffer[i])) & 0xFF)] }
        }
        return (size, crc ^ 0xFFFF_FFFF)
    }

    private static func write(_ bytes: [UInt8], to out: OutputStream) throws -> Int {
        var idx = 0, total = 0
        try bytes.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw ZipError(message: "Output stream write failed")
            }
            while idx < bytes.count {
                let n = out.write(base.advanced(by: idx), maxLength: bytes.count - idx)
                if n <= 0 { throw ZipError(message: "Output stream write failed") }
                idx += n; total += n
            }
        }
        return total
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
    private static func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)] }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
}
