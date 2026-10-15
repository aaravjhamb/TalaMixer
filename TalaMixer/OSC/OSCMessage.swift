//
//  OSCMessage.swift
//  TalaMixer
//
//  Minimal OSC 1.0 encoder/decoder. The X-Air firmware only ever uses the four
//  core argument types (int32, float32, string, blob), so that is all we model.
//

import Foundation

/// A single OSC argument.
enum OSCValue: Equatable, Sendable {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob(Data)

    /// The X-Air firmware is loose about int-vs-float for some parameters
    /// (`/ch/01/mix/on` answers `1` but a few builds answer `1.0`), so the
    /// accessors coerce rather than insisting on an exact case match.
    var intValue: Int? {
        switch self {
        case .int(let v): return Int(v)
        case .float(let v): return Int(v.rounded())
        case .string(let v): return Int(v)
        case .blob: return nil
        }
    }

    var floatValue: Float? {
        switch self {
        case .int(let v): return Float(v)
        case .float(let v): return v
        case .string(let v): return Float(v)
        case .blob: return nil
        }
    }

    var boolValue: Bool? {
        guard let i = intValue else { return nil }
        return i != 0
    }

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .float(let v): return String(v)
        case .blob: return nil
        }
    }

    var blobValue: Data? {
        if case .blob(let d) = self { return d }
        return nil
    }

    /// The OSC type tag character for this value.
    var typeTag: Character {
        switch self {
        case .int: return "i"
        case .float: return "f"
        case .string: return "s"
        case .blob: return "b"
        }
    }
}

/// An OSC message: an address pattern plus zero or more arguments.
struct OSCMessage: Equatable, Sendable {
    var address: String
    var values: [OSCValue]

    init(_ address: String, _ values: [OSCValue] = []) {
        self.address = address
        self.values = values
    }

    init(_ address: String, _ value: OSCValue) {
        self.init(address, [value])
    }

    // Convenience constructors for the shapes we send constantly.
    static func query(_ address: String) -> OSCMessage { OSCMessage(address) }
    static func set(_ address: String, _ value: Float) -> OSCMessage { OSCMessage(address, .float(value)) }
    static func set(_ address: String, _ value: Int) -> OSCMessage { OSCMessage(address, .int(Int32(value))) }
    static func set(_ address: String, _ value: Bool) -> OSCMessage { OSCMessage(address, .int(value ? 1 : 0)) }
    static func set(_ address: String, _ value: String) -> OSCMessage { OSCMessage(address, .string(value)) }

    // MARK: - Encoding

    func encoded() -> Data {
        var out = Data()
        out.appendOSCString(address)

        var tags = ","
        for v in values { tags.append(v.typeTag) }
        out.appendOSCString(tags)

        for v in values {
            switch v {
            case .int(let i):
                out.appendBigEndian(UInt32(bitPattern: i))
            case .float(let f):
                out.appendBigEndian(f.bitPattern)
            case .string(let s):
                out.appendOSCString(s)
            case .blob(let d):
                out.appendBigEndian(UInt32(d.count))
                out.append(d)
                out.appendPadding(to: 4)
            }
        }
        return out
    }

    // MARK: - Decoding

    /// Decodes a datagram into one or more messages, transparently unwrapping
    /// `#bundle` containers.
    static func decode(_ data: Data) -> [OSCMessage] {
        var reader = ByteReader(data)
        return decodeElements(&reader, count: 1)
    }

    private static func decodeElements(_ reader: inout ByteReader, count: Int) -> [OSCMessage] {
        var results: [OSCMessage] = []
        guard let first = reader.peekOSCString() else { return results }

        if first == "#bundle" {
            _ = reader.readOSCString()          // "#bundle"
            _ = reader.read(8)                  // OSC time tag — unused here
            while let size = reader.readUInt32(), let element = reader.read(Int(size)) {
                var sub = ByteReader(element)
                results.append(contentsOf: decodeElements(&sub, count: 1))
            }
            return results
        }

        if let message = decodeMessage(&reader) {
            results.append(message)
        }
        return results
    }

    private static func decodeMessage(_ reader: inout ByteReader) -> OSCMessage? {
        guard let address = reader.readOSCString() else { return nil }

        // A few X-Air replies (notably `/status`) omit the type tag string
        // entirely. Treat a missing tag as "no arguments" rather than failing.
        guard let tags = reader.readOSCString(), tags.hasPrefix(",") else {
            return OSCMessage(address)
        }

        var values: [OSCValue] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "i":
                guard let raw = reader.readUInt32() else { return OSCMessage(address, values) }
                values.append(.int(Int32(bitPattern: raw)))
            case "f":
                guard let raw = reader.readUInt32() else { return OSCMessage(address, values) }
                values.append(.float(Float(bitPattern: raw)))
            case "s", "S":
                guard let s = reader.readOSCString() else { return OSCMessage(address, values) }
                values.append(.string(s))
            case "b":
                guard let size = reader.readUInt32(),
                      let d = reader.read(Int(size)) else { return OSCMessage(address, values) }
                reader.align(to: 4)
                values.append(.blob(d))
            case "T": values.append(.int(1))
            case "F": values.append(.int(0))
            case "N", "I":
                break   // null / infinitum carry no data
            default:
                // Unknown tag: we can't know its width, so stop parsing args.
                return OSCMessage(address, values)
            }
        }
        return OSCMessage(address, values)
    }
}

// MARK: - Byte helpers

private extension Data {
    mutating func appendPadding(to alignment: Int) {
        let remainder = count % alignment
        if remainder != 0 {
            append(Data(repeating: 0, count: alignment - remainder))
        }
    }

    /// OSC strings are null-terminated and padded with nulls to a multiple of 4.
    mutating func appendOSCString(_ string: String) {
        append(contentsOf: Array(string.utf8))
        append(0)
        appendPadding(to: 4)
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }
}

/// A cursor over a `Data` buffer with the alignment rules OSC needs.
struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        self.bytes = [UInt8](data)
    }

    var remaining: Int { bytes.count - offset }

    mutating func read(_ count: Int) -> Data? {
        guard count >= 0, remaining >= count else { return nil }
        defer { offset += count }
        return Data(bytes[offset..<(offset + count)])
    }

    mutating func readUInt32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    mutating func align(to alignment: Int) {
        let remainder = offset % alignment
        if remainder != 0 { offset = min(bytes.count, offset + alignment - remainder) }
    }

    mutating func readOSCString() -> String? {
        guard remaining > 0 else { return nil }
        var end = offset
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        guard end < bytes.count else { return nil }   // unterminated
        let string = String(decoding: bytes[offset..<end], as: UTF8.self)
        offset = end + 1
        align(to: 4)
        return string
    }

    func peekOSCString() -> String? {
        var copy = self
        return copy.readOSCString()
    }
}
